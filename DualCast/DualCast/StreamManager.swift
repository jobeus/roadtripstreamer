import Foundation
import AVFoundation
import HaishinKit
import Combine

@MainActor
class StreamManager: NSObject, ObservableObject {
    let connection = RTMPConnection()
    let stream: RTMPStream
    
    @Published var isStreaming = false
    @Published var connectionStatus = "Disconnected"
    
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
        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            do {
                try stream.attachCamera(camera)
            } catch {
                print("Failed to attach camera: \(error)")
            }
        }
        
        if let mic = AVCaptureDevice.default(for: .audio) {
            do {
                try stream.attachAudio(mic)
            } catch {
                print("Failed to attach audio: \(error)")
            }
        }
    }
    
    func startStreaming(rtmpURL: String, streamKey: String) {
        guard !isStreaming, !streamKey.isEmpty else { return }
        
        connectionStatus = "Connecting..."
        // In basic streaming, the connection URL to Twitch is the rtmpURL,
        // and when connect is successful, stream.publish(streamKey) is called.
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
