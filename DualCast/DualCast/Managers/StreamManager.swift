import UIKit
import AVFoundation
@preconcurrency import HaishinKit
import Combine

@MainActor
class StreamManager: NSObject, ObservableObject {
    let connection = RTMPConnection()
    let stream: RTMPStream
    
    @Published var isStreaming = false
    @Published var connectionStatus = "Disconnected"
    
    @Published var isMuted: Bool = false {
        didSet { stream.audioMixerSettings.isMuted = isMuted }
    }
    
    @Published var isFrontCameraMain: Bool = false {
        didSet { updatePiP() }
    }
    
    @Published var isPiPVisible: Bool = true {
        didSet { updatePiP() }
    }
    
    @Published var isMapVisible: Bool = true {
        didSet { mapObject?.isVisible = isMapVisible }
    }
    
    @Published var isZoomedToRoute: Bool = false
    @Published var currentCityState: String?
    
    private var pipObject: VideoTrackScreenObject?
    private var mapObject: ImageScreenObject?
    
    @Published var isCameraReady: Bool = false
    
    // Background Paused Video Generator
    private var backgroundGenerator: BackgroundFrameGenerator?
    
    @Published var isAppBackgrounded: Bool = false {
        didSet {
            guard oldValue != isAppBackgrounded else { return }
            handleBackgroundStateChange()
        }
    }
    
    @Published var isRecordingEnabled: Bool = false
    private let recorder = IOStreamRecorder()
    
    private var isIntentionalDisconnect = false
    
    private static let supportsBackgroundMultiCam: Bool = {
        if #available(iOS 16.0, *) {
            return AVCaptureSession().isMultitaskingCameraAccessSupported
        }
        return false
    }()

    
    override init() {
        self.stream = RTMPStream(connection: connection)
        super.init()
        
        connection.addEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
        
        backgroundGenerator = BackgroundFrameGenerator(stream: stream)
    }
    
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .videoChat, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }
    
    func initializeCameras() async {
        let videoAuth = await AVCaptureDevice.requestAccess(for: .video)
        let audioAuth = await AVCaptureDevice.requestAccess(for: .audio)
            
        guard videoAuth && audioAuth else {
            print("Camera/Mic permissions not granted.")
            return
        }
        
        // Yield the main thread to allow the Splash Screen to physically render and animate
        // By delaying 1.5 seconds, we ensure the UI is fully visible before locking the thread for camera init
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        
        self.setupAudioSession()
        self.attachCameras()
    }

    private func attachCameras() {
        let multiCamSupported = AVCaptureMultiCamSession.isMultiCamSupported
        let videoSize = CGSize(width: 1280, height: 720) 
        stream.videoSettings.videoSize = videoSize 
        stream.frameRate = 30
        
        if multiCamSupported {
            stream.isMultiCamSessionEnabled = true
            
            stream.configuration { @Sendable session in
                if #available(iOS 16.0, *),
                   session.isMultitaskingCameraAccessSupported {
                    session.isMultitaskingCameraAccessEnabled = true
                }
            }
            
            stream.videoOrientation = .landscapeRight
            stream.videoMixerSettings.mode = .offscreen
            stream.screen.size = videoSize
            
            if pipObject == nil {
                let pip = VideoTrackScreenObject()
                pip.track = 1 
                self.pipObject = pip
                try? stream.screen.addChild(pip)
            }
            
            if mapObject == nil {
                let mapOverlay = ImageScreenObject()
                mapOverlay.cgImage = nil
                self.mapObject = mapOverlay
                try? stream.screen.addChild(mapOverlay)
                setupMapLayout()
            }
            
            updatePiP()
            
            stream.screen.startRunning()
            
            // Back camera (track 0)
            if let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                stream.attachCamera(back, track: 0)
            }
            
            // Front camera (track 1)
            if let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                stream.attachCamera(front, track: 1) { @Sendable captureUnit, _ in
                    captureUnit?.isVideoMirrored = true
                }
            }
        } else {
            print("MultiCam not supported! Fallback to single camera.")
            stream.videoMixerSettings.mode = .passthrough
            stream.sessionPreset = .hd1280x720
            
            if let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                stream.attachCamera(back, track: 0)
            }
        }
        
        if let mic = AVCaptureDevice.default(for: .audio) {
            stream.attachAudio(mic)
        }
        
        // Signal that the UI and streams are ready
        self.isCameraReady = true
    }
    
    private func handleBackgroundStateChange() {
        guard AVCaptureMultiCamSession.isMultiCamSupported else { return }
        
        if !Self.supportsBackgroundMultiCam {
            if isAppBackgrounded {
                print("Falling back to Audio-Only Mode to prevent background crash...")
                stream.isMultiCamSessionEnabled = false
                stream.videoMixerSettings.mode = .passthrough
                
                // Remove ALL video inputs. Since iPhone cannot PiP a replaced session, the camera
                // drops entirely and sends a black frame. Audio (Mic) and RTMP stay fully connected!
                stream.attachCamera(nil, track: 0)
                stream.attachCamera(nil, track: 1)
                
                // Start pumping the "PAUSED" image directly into the RTMP multiplexer so the network socket doesn't starve
                backgroundGenerator?.start()
                
            } else {
                print("Restoring MultiCam Session in foreground...")
                backgroundGenerator?.stop()
                
                stream.isMultiCamSessionEnabled = true
                stream.videoMixerSettings.mode = .offscreen
                
                if let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                    stream.attachCamera(back, track: 0)
                }
                if let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                    stream.attachCamera(front, track: 1) { @Sendable captureUnit, _ in
                        captureUnit?.isVideoMirrored = true
                    }
                }
                
                updatePiP()
            }
        }
    }
    
    private func updatePiP() {
        guard let pip = pipObject else { return }
        
        // Swap tracks based on which is main
        stream.videoMixerSettings.mainTrack = isFrontCameraMain ? 1 : 0
        pip.track = isFrontCameraMain ? 0 : 1
        
        // Determine layout based on current video resolution
        let w = stream.videoSettings.videoSize.width
        let h = stream.videoSettings.videoSize.height
        
        let pipW = w * 0.25
        let pipH = h * 0.25
        
        pip.size = CGSize(width: pipW, height: pipH)
        
        #if os(macOS)
        pip.layoutMargin = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        #else
        pip.layoutMargin = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        #endif
        
        pip.verticalAlignment = .bottom
        pip.horizontalAlignment = .right
        
        pip.isVisible = isPiPVisible
        
        // Position map overlay (top right by default for Twitch)
        if let map = mapObject {
            map.isVisible = isMapVisible
        }
    }
    
    private func setupMapLayout() {
        guard let map = mapObject else { return }
        // Exact target size: 256x192 (20% of 1280)
        map.size = CGSize(width: 256, height: 192)
        #if os(macOS)
        map.layoutMargin = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        #else
        map.layoutMargin = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        #endif
        map.verticalAlignment = .top
        map.horizontalAlignment = .right
    }
    
    func updateMapImage(_ cgImage: CGImage?) {
        guard let mapObject = self.mapObject else { return }
        stream.lockQueue.async {
            mapObject.cgImage = cgImage
        }
    }
    
    func startStreaming(rtmpURL: String, streamKey: String) {
        guard !isStreaming, !streamKey.isEmpty else { return }
        
        isIntentionalDisconnect = false
        connectionStatus = "Connecting..."
        connection.connect(rtmpURL)
    }
    
    func stopStreaming() {
        isIntentionalDisconnect = true
        connection.close()
        isStreaming = false
        connectionStatus = "Disconnected"
    }
    
    @objc nonisolated private func rtmpStatusHandler(_ notification: Notification) {
        let e = Event.from(notification)
        guard let data = e.data as? ASObject, let code = data["code"] as? String else { return }
        
        print("RTMP Status: \(code)")
        Task { @MainActor in
            switch code {
            case RTMPConnection.Code.connectSuccess.rawValue:
                self.connectionStatus = "Live"
                self.isStreaming = true
                self.stream.publish(UserDefaults.standard.string(forKey: "twitchStreamKey") ?? "")
                if self.isRecordingEnabled {
                    self.stream.addObserver(self.recorder)
                    self.recorder.startRunning()
                }
            case RTMPConnection.Code.connectClosed.rawValue:
                self.connectionStatus = "Disconnected"
                self.isStreaming = false
                self.recorder.stopRunning()
                self.stream.removeObserver(self.recorder)
                self.handleReconnect()
            case RTMPConnection.Code.connectFailed.rawValue, RTMPConnection.Code.connectRejected.rawValue:
                self.connectionStatus = "Failed"
                self.isStreaming = false
                self.recorder.stopRunning()
                self.stream.removeObserver(self.recorder)
                self.handleReconnect()
            default:
                break
            }
        }
    }
    
    private func handleReconnect() {
        guard !isIntentionalDisconnect else { return }
        print("Connection lost, attempting to reconnect...")
        self.connectionStatus = "Reconnecting..."
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self, !self.isIntentionalDisconnect else { return }
            let rtmpURL = UserDefaults.standard.string(forKey: "rtmpURL") ?? "rtmp://live.twitch.tv/app/"
            self.connection.connect(rtmpURL)
        }
    }
}


