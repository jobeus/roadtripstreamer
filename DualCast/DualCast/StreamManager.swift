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
        
        await MainActor.run {
            self.setupAudioSession()
            self.attachCameras()
        }
    }

    private func attachCameras() {
        let multiCamSupported = AVCaptureMultiCamSession.isMultiCamSupported
        let videoSize = CGSize(width: 1280, height: 720) 
        stream.videoSettings.videoSize = videoSize 
        stream.frameRate = 30
        
        if multiCamSupported {
            stream.isMultiCamSessionEnabled = true
            
            stream.configuration { session in
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
            }
            
            updatePiP()
            
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
        
        // Signal that the UI and streams are ready
        self.isCameraReady = true
    }
    
    private func handleBackgroundStateChange() {
        guard AVCaptureMultiCamSession.isMultiCamSupported else { return }
        
        var supportsBackgroundMultiCam = false
        if #available(iOS 16.0, *) {
            supportsBackgroundMultiCam = AVCaptureSession().isMultitaskingCameraAccessSupported
        }
        
        if !supportsBackgroundMultiCam {
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
                    stream.attachCamera(front, track: 1) { captureUnit, _ in
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

class BackgroundFrameGenerator {
    private var timer: Timer?
    private var pixelBuffer: CVPixelBuffer?
    private weak var stream: RTMPStream?
    
    init(stream: RTMPStream) {
        self.stream = stream
        createPausedPixelBuffer()
    }
    
    private func createPausedPixelBuffer() {
        let size = CGSize(width: 1280, height: 720)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            
            let colors = [UIColor.darkGray.cgColor, UIColor.black.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: size.width/2, y: size.height/2),
                    startRadius: 0,
                    endCenter: CGPoint(x: size.width/2, y: size.height/2),
                    endRadius: size.width/2,
                    options: .drawsBeforeStartLocation
                )
            }
            
            let text = "STREAM PAUSED\n(Audio is Live)"
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 100, weight: .black),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            
            let textSize = text.size(withAttributes: attrs)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            text.draw(in: textRect, withAttributes: attrs)
        }
        
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, attrs, &buffer)
        
        guard let pb = buffer, let cgImage = image.cgImage else { return }
        
        CVPixelBufferLockBaseAddress(pb, [])
        let cgContext = CGContext(
            data: CVPixelBufferGetBaseAddress(pb),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        
        if let ctx = cgContext {
            ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        self.pixelBuffer = pb
    }
    
    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            guard let self = self, let pb = self.pixelBuffer, let stream = self.stream else { return }
            
            let now = CMClockGetTime(CMClockGetHostTimeClock())
            var sampleTime = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: 15),
                presentationTimeStamp: now,
                decodeTimeStamp: .invalid
            )
            
            var formatDesc: CMFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb, formatDescriptionOut: &formatDesc)
            
            var sampleBuffer: CMSampleBuffer?
            guard let fd = formatDesc else { return }
            
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pb,
                formatDescription: fd,
                sampleTiming: &sampleTime,
                sampleBufferOut: &sampleBuffer
            )
            
            if let sb = sampleBuffer {
                stream.append(sb)
            }
        }
        
        if let t = timer {
            RunLoop.main.add(t, forMode: .common)
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

