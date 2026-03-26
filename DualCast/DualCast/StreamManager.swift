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
    
    private var pipObject: VideoTrackScreenObject?
    
    override init() {
        self.stream = RTMPStream(connection: connection)
        super.init()
        
        setupAudioSession()
        setupCameras()
        
        connection.addEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
    }
    
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }
    
    private func setupCameras() {
        // Enable multi-cam and offscreen rendering for PiP compositing
        stream.isMultiCamSessionEnabled = true
        stream.videoMixerSettings.mode = .offscreen
        stream.videoSettings.videoSize = CGSize(width: 1280, height: 720) // Default 720p Landscape
        
        // Back camera (track 0)
        if let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            stream.attachCamera(back, track: 0)
        }
        
        // Front camera (track 1)
        if let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            stream.attachCamera(front, track: 1)
        }
        
        if let mic = AVCaptureDevice.default(for: .audio) {
            stream.attachAudio(mic)
        }
        
        // Add PiP object to screen
        let pip = VideoTrackScreenObject()
        // Ensure bounds are set, position will be updated in updatePiP
        try? stream.screen.addChild(pip)
        self.pipObject = pip
        
        updatePiP()
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
            case RTMPConnection.Code.connectClosed.rawValue:
                self.connectionStatus = "Disconnected"
                self.isStreaming = false
            case RTMPConnection.Code.connectFailed.rawValue, RTMPConnection.Code.connectRejected.rawValue:
                self.connectionStatus = "Failed"
                self.isStreaming = false
            default:
                break
            }
        }
    }
}

