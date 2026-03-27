import UIKit
import AVFoundation
import HaishinKit
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
    @Published var pipCorner: Int = 3 { // 0: TL, 1: TR, 2: BL, 3: BR
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
    
    @Published var isRecordingEnabled: Bool = false
    private let recorder = IOStreamRecorder()

    
    override init() {
        self.stream = RTMPStream(connection: connection)
        super.init()
        
        setupCameras()
        
        connection.addEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
    }
    
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }
    
    private func setupCameras() {
        Task {
            let videoAuth = await AVCaptureDevice.requestAccess(for: .video)
            let audioAuth = await AVCaptureDevice.requestAccess(for: .audio)
            
            guard videoAuth && audioAuth else {
                print("Camera/Mic permissions not granted.")
                return
            }
            
            await MainActor.run {
                self.setupAudioSession()
                self.attachCameras()
            }
        }
    }

    private func attachCameras() {
        let multiCamSupported = AVCaptureMultiCamSession.isMultiCamSupported
        let videoSize = CGSize(width: 1280, height: 720) 
        stream.videoSettings.videoSize = videoSize 
        stream.frameRate = 30
        
        if multiCamSupported {
            stream.isMultiCamSessionEnabled = true
            stream.videoOrientation = .landscapeRight
            stream.videoMixerSettings.mode = .offscreen
            stream.screen.size = videoSize
            
            let pip = VideoTrackScreenObject()
            pip.track = 1 
            self.pipObject = pip
            
            let mapOverlay = ImageScreenObject()
            mapOverlay.cgImage = nil
            self.mapObject = mapOverlay
            
            updatePiP()
            
            try? stream.screen.addChild(pip)
            try? stream.screen.addChild(mapOverlay)
            
            stream.screen.startRunning()
            
            // Back camera (track 0)
            if let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                stream.attachCamera(back, track: 0)
            }
            
            // Front camera (track 1)
            if let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                stream.attachCamera(front, track: 1) { captureUnit, _ in
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
        
        // HaishinKit ScreenObject uses horizontal/vertical alignments
        switch pipCorner {
        case 0: // Top Left
            pip.verticalAlignment = .top
            pip.horizontalAlignment = .left
        case 1: // Top Right
            pip.verticalAlignment = .top
            pip.horizontalAlignment = .right
        case 2: // Bottom Left
            pip.verticalAlignment = .bottom
            pip.horizontalAlignment = .left
        case 3: // Bottom Right
            pip.verticalAlignment = .bottom
            pip.horizontalAlignment = .right
        default: break
        }
        
        pip.isVisible = isPiPVisible
        
        // Position map overlay (top right by default for Twitch)
        if let map = mapObject {
            // Exact target size: 256x192 (20% of 1280)
            map.size = CGSize(width: 256, height: 192)
            #if os(macOS)
            map.layoutMargin = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
            #else
            map.layoutMargin = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
            #endif
            map.verticalAlignment = .top
            map.horizontalAlignment = .right
            map.isVisible = isMapVisible
        }
    }
    
    func updateMapImage(_ cgImage: CGImage?) {
        guard let mapObject = self.mapObject else { return }
        stream.lockQueue.async {
            mapObject.cgImage = cgImage
        }
    }
    
    func startStreaming(rtmpURL: String, streamKey: String) {
        guard !isStreaming, !streamKey.isEmpty else { return }
        
        connectionStatus = "Connecting..."
        connection.connect(rtmpURL)
    }
    
    func stopStreaming() {
        connection.close()
        isStreaming = false
        connectionStatus = "Disconnected"
    }
    
    @objc private func rtmpStatusHandler(_ notification: Notification) {
        let e = Event.from(notification)
        guard let data = e.data as? ASObject, let code = data["code"] as? String else { return }
        
        print("RTMP Status: \(code)")
        DispatchQueue.main.async {
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
            case RTMPConnection.Code.connectFailed.rawValue, RTMPConnection.Code.connectRejected.rawValue:
                self.connectionStatus = "Failed"
                self.isStreaming = false
                self.recorder.stopRunning()
                self.stream.removeObserver(self.recorder)
            default:
                break
            }
        }
    }
}

