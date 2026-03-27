import SwiftUI
import HaishinKit
import AVFoundation

struct StreamView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var streamManager = StreamManager()
    @StateObject private var chatManager = TwitchChatManager()
    @StateObject private var routeTracker = RouteTracker()
    @StateObject private var thermalMonitor = ThermalMonitor()
    @State private var showingSettings = false
    @State private var showChat = true
    @State private var showMap = true
    @State private var isPanicMode = false
    @State private var isActuallyPaused = false
    @State private var panicBlink = false
    @State private var unreadChat = 0
    
    var body: some View {
        ZStack {
            // Invisible Map for snapshotting (must be in view hierarchy but hidden)
            // It will be composited onto the stream and visible via HKViewRepresentation
            MapOverlayView(
                routeCoordinates: routeTracker.routeCoordinates,
                currentLocation: routeTracker.currentLocation,
                streamManager: streamManager,
                isAppBackgrounded: scenePhase == .background
            )
            .frame(width: 256, height: 192) // 4:3 PiP size
            .opacity(0.01) // Invisible to user, but still renders for snapshot
            .allowsHitTesting(false)
            
            // Background Camera Preview
            HKViewRepresentation(stream: streamManager.stream, isStreaming: streamManager.isStreaming)
                .ignoresSafeArea()
                .background(Color.black)
            
            if !isPanicMode {
                // === NORMAL UI ===
                normalControls
                
                // Chat Overlay
                if showChat && !chatManager.messages.isEmpty {
                    chatOverlay
                }
                
                // Map Tap Target
                if showMap {
                    VStack {
                        HStack {
                            Spacer()
                            Color.white.opacity(0.001)
                                .frame(width: 256, height: 192)
                                .padding(20)
                                .onTapGesture {
                                    streamManager.isZoomedToRoute.toggle()
                                }
                        }
                        Spacer()
                    }
                }
            } else {
                // === PANIC MODE: Fake "Paused" Screen ===
                panicOverlay
            }

            // Splash Screen Overlay
            if !streamManager.isCameraReady {
                SplashScreenView()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(.easeOut(duration: 0.5), value: streamManager.isCameraReady)
        .task {
            await streamManager.initializeCameras()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(routeTracker)
        }
        .onChange(of: routeTracker.currentCityState) { _, newValue in
            streamManager.currentCityState = newValue
        }
        .onChange(of: showMap) { _, newValue in
            streamManager.isMapVisible = newValue
        }
        .onChange(of: appState.saveLocalRecording) { _, newValue in
            streamManager.isRecordingEnabled = newValue
        }
        .onChange(of: streamManager.isStreaming) { _, streaming in
            if streaming {
                chatManager.connect()
                routeTracker.startTracking()
            } else {
                chatManager.disconnect()
                routeTracker.stopTracking()
            }
        }
        .onChange(of: chatManager.messages.count) { _, _ in
            if !showChat { unreadChat += 1 }
        }
        .onAppear {
            routeTracker.startTracking()
        }
        .onChange(of: scenePhase) { _, phase in
            // Treat .inactive (like swiping into PiP) or .background as backgrounded to ensure we drop MultiCam early enough
            streamManager.isAppBackgrounded = (phase != .active)
        }
    }
    
    // MARK: - Normal Controls
    private var normalControls: some View {
        VStack {
            // Top Bar
            HStack {
                if streamManager.isStreaming {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                    Text("LIVE")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    if thermalMonitor.isCritical {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                            .font(.title2)
                            .padding(.leading, 8)
                            .symbolEffect(.pulse, options: .repeating)
                    }
                    
                    // Panic Mode button (only while live)
                    Button(action: { isPanicMode = true }) {
                        Image(systemName: "eye.slash.fill")
                            .font(.title3)
                            .foregroundColor(.yellow)
                            .padding(8)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 8)
                } else {
                    Text(streamManager.connectionStatus)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                
                Spacer() // Pushes the top-bar items to the left
            }
            .padding()
            
            Spacer() // Pushes everything else to the bottom
            
            // Bottom Controls (ALL BOTTOM ROW)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    if streamManager.isStreaming {
                        Button(action: {
                            showChat.toggle()
                            if showChat { unreadChat = 0 }
                        }) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: showChat ? "bubble.left.fill" : "bubble.left")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                                
                                if !showChat && unreadChat > 0 {
                                    Text("\(min(unreadChat, 99))")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(4)
                                        .background(Color.red)
                                        .clipShape(Circle())
                                        .offset(x: 4, y: -4)
                                }
                            }
                        }
                    }
                    
                    Button(action: { showMap.toggle() }) {
                        Image(systemName: showMap ? "map.fill" : "map")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    Button(action: { showingSettings.toggle() }) {
                        Image(systemName: "gear")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    Button(action: {
                        streamManager.isMuted.toggle()
                    }) {
                        Image(systemName: streamManager.isMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.title2)
                            .foregroundColor(streamManager.isMuted ? .red : .white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    Button(action: {
                        streamManager.isFrontCameraMain.toggle()
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    Button(action: {
                        streamManager.isPiPVisible.toggle()
                    }) {
                        Image(systemName: streamManager.isPiPVisible ? "person.2.fill" : "person.fill")
                            .font(.title2)
                            .foregroundColor(streamManager.isPiPVisible ? .white : .gray)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    Button(action: {
                        if streamManager.isStreaming {
                            streamManager.stopStreaming()
                        } else {
                            streamManager.startStreaming(rtmpURL: appState.rtmpURL, streamKey: appState.twitchStreamKey)
                        }
                    }) {
                        Text(streamManager.isStreaming ? "STOP STREAM" : "GO LIVE")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(streamManager.isStreaming ? Color.red : Color.blue)
                            .cornerRadius(25)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
    
    // MARK: - Chat Overlay
    private var chatOverlay: some View {
        VStack {
            Spacer()
            HStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(chatManager.messages) { msg in
                                HStack(alignment: .top, spacing: 4) {
                                    Text(msg.timestamp, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    Text(msg.username + ":")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(colorFromHex(msg.color))
                                    Text(msg.message)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                                .id(msg.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: chatManager.messages.count) { _, _ in
                        if let last = chatManager.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .frame(maxWidth: 300, maxHeight: 200)
                .background(Color.black.opacity(0.4))
                .cornerRadius(12)
                
                Spacer()
            }
            .padding(.leading, 16)
            .padding(.bottom, 70) // Above bottom controls
        }
    }
    
    // MARK: - Panic Mode Overlay
    private var panicOverlay: some View {
        ZStack {
            // Full opaque black screen
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(isActuallyPaused ? (panicBlink ? .red : .white) : .white)
                
                Text("Stream Paused")
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundColor(isActuallyPaused ? (panicBlink ? .red : .white) : .white)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: panicBlink)
                
                Text("Double-tap to resume")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.4))
            }
            .onChange(of: isActuallyPaused) { _, paused in
                panicBlink = paused
            }
        }
        // Long-press anywhere = ACTUALLY pause the stream (secret)
        .onLongPressGesture(minimumDuration: 2.0) {
            isActuallyPaused.toggle()
            streamManager.stream.paused = isActuallyPaused
        }
        // Double-tap = dismiss the fake overlay
        .onTapGesture(count: 2) {
            isPanicMode = false
            if isActuallyPaused {
                isActuallyPaused = false
                streamManager.stream.paused = false
            }
        }
    }
    
    // MARK: - Helpers
    private func colorFromHex(_ hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else {
            return .white
        }
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}

import AVKit

// MARK: - PiP Manager for Stream
class PiPManager: NSObject, AVPictureInPictureControllerDelegate {
    private var pipController: AVPictureInPictureController?
    private var pipVideoCallViewController: AVPictureInPictureVideoCallViewController?
    private var pipSource: AVPictureInPictureController.ContentSource?
    private weak var sourceView: MTHKView?
    private weak var sourceViewSuperview: UIView?
    
    func setupPiP(with sourceView: MTHKView, container: UIView) {
        self.sourceView = sourceView
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        
        let pipVC = AVPictureInPictureVideoCallViewController()
        pipVC.view.backgroundColor = .black
        self.pipVideoCallViewController = pipVC
        
        self.pipSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: container,
            contentViewController: pipVC
        )
    }
    
    func setPiPActive(_ active: Bool) {
        if active {
            if pipController == nil, let source = pipSource {
                let pip = AVPictureInPictureController(contentSource: source)
                pip.delegate = self
                pip.canStartPictureInPictureAutomaticallyFromInline = true
                self.pipController = pip
            }
        } else {
            pipController?.canStartPictureInPictureAutomaticallyFromInline = false
            pipController = nil
        }
    }
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard let sourceView = sourceView, let pipVC = pipVideoCallViewController else { return }
        self.sourceViewSuperview = sourceView.superview
        
        sourceView.removeFromSuperview()
        sourceView.translatesAutoresizingMaskIntoConstraints = false
        pipVC.view.addSubview(sourceView)
        NSLayoutConstraint.activate([
            sourceView.leadingAnchor.constraint(equalTo: pipVC.view.leadingAnchor),
            sourceView.trailingAnchor.constraint(equalTo: pipVC.view.trailingAnchor),
            sourceView.topAnchor.constraint(equalTo: pipVC.view.topAnchor),
            sourceView.bottomAnchor.constraint(equalTo: pipVC.view.bottomAnchor)
        ])
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard let sourceView = sourceView, let superview = sourceViewSuperview else { return }
        
        sourceView.removeFromSuperview()
        sourceView.translatesAutoresizingMaskIntoConstraints = true
        sourceView.frame = superview.bounds
        sourceView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        superview.addSubview(sourceView)
    }
}

// SwiftUI wrapper for HaishinKit's MTHKView with PiP
struct HKViewRepresentation: UIViewRepresentable {
    let stream: RTMPStream
    var isStreaming: Bool
    
    class Coordinator {
        let pipManager = PiPManager()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.backgroundColor = .black
        
        let view = MTHKView(frame: .zero)
        view.videoGravity = AVLayerVideoGravity.resizeAspectFill
        view.attachStream(stream)
        
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.frame = container.bounds
        container.addSubview(view)
        
        DispatchQueue.main.async {
            context.coordinator.pipManager.setupPiP(with: view, container: container)
            context.coordinator.pipManager.setPiPActive(self.isStreaming)
        }
        
        return container
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.pipManager.setPiPActive(isStreaming)
    }
}

// MARK: - Splash Screen View
struct SplashScreenView: View {
    @State private var iconScale: CGFloat = 0.8
    @State private var iconOpacity: Double = 0.0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                if let icon = UIImage(named: "AppIcon") {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .cornerRadius(24)
                        .shadow(color: .white.opacity(0.1), radius: 10, x: 0, y: 0)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "video.badge.waveform")
                            .font(.system(size: 50, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                Text("DualCast")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(2)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
                    .padding(.top, 10)
            }
            .scaleEffect(iconScale)
            .opacity(iconOpacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    iconScale = 1.0
                    iconOpacity = 1.0
                }
            }
        }
    }
}

