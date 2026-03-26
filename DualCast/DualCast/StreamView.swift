import SwiftUI
import HaishinKit
import AVFoundation

struct StreamView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var streamManager = StreamManager()
    @StateObject private var chatManager = TwitchChatManager()
    @State private var showingSettings = false
    @State private var showChat = true
    @State private var isPanicMode = false
    @State private var isActuallyPaused = false
    @State private var panicBlink = false
    @State private var unreadChat = 0
    
    var body: some View {
        ZStack {
            // Background Camera Preview
            HKViewRepresentation(stream: streamManager.stream)
                .ignoresSafeArea()
                .background(Color.black)
            
            if !isPanicMode {
                // === NORMAL UI ===
                normalControls
                
                // Chat Overlay
                if showChat && !chatManager.messages.isEmpty {
                    chatOverlay
                }
            } else {
                // === PANIC MODE: Fake "Paused" Screen ===
                panicOverlay
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .onChange(of: streamManager.isStreaming) { streaming in
            if streaming {
                chatManager.connect()
            } else {
                chatManager.disconnect()
            }
        }
        .onChange(of: chatManager.messages.count) { _ in
            if !showChat { unreadChat += 1 }
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
                
                Spacer()
                
                // Chat toggle (only while streaming)
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
                
                Button(action: { showingSettings.toggle() }) {
                    Image(systemName: "gear")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
            }
            .padding()
            
            Spacer()
            
            // Bottom Controls
            HStack(spacing: 20) {
                // Mute Toggle
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
                
                // PiP Corner Toggle
                Button(action: {
                    streamManager.pipCorner = (streamManager.pipCorner + 1) % 4
                }) {
                    Image(systemName: "pip.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                
                Spacer()
                
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
                        .padding()
                        .frame(minWidth: 150)
                        .background(streamManager.isStreaming ? Color.red : Color.blue)
                        .cornerRadius(25)
                }
                
                Spacer()
                
                // Camera Swap
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
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 20)
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
                    .onChange(of: chatManager.messages.count) { _ in
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
            .onChange(of: isActuallyPaused) { paused in
                panicBlink = paused
            }
        }
        // Long-press anywhere = ACTUALLY pause the stream (secret)
        .onLongPressGesture(minimumDuration: 2.0) {
            isActuallyPaused.toggle()
            (streamManager.stream as? RTMPStream)?.paused = isActuallyPaused
        }
        // Double-tap = dismiss the fake overlay
        .onTapGesture(count: 2) {
            isPanicMode = false
            if isActuallyPaused {
                isActuallyPaused = false
                (streamManager.stream as? RTMPStream)?.paused = false
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

// SwiftUI wrapper for HaishinKit's MTHKView
struct HKViewRepresentation: UIViewRepresentable {
    let stream: RTMPStream
    
    func makeUIView(context: Context) -> MTHKView {
        let view = MTHKView(frame: UIScreen.main.bounds)
        view.videoGravity = AVLayerVideoGravity.resizeAspectFill
        view.attachStream(stream)
        return view
    }
    
    func updateUIView(_ uiView: MTHKView, context: Context) {
        // No update needed
    }
}
