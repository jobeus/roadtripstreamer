import SwiftUI
import HaishinKit
import AVFoundation

struct StreamView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var streamManager = StreamManager()
    @State private var showingSettings = false
    
    var body: some View {
        ZStack {
            // Background Camera Preview
            HKViewRepresentation(stream: streamManager.stream)
                .ignoresSafeArea()
                .background(Color.black)
            
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
                    } else {
                        Text(streamManager.connectionStatus)
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
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
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// SwiftUI wrapper for HaishinKit's MTHKView
struct HKViewRepresentation: UIViewRepresentable {
    let stream: RTMPStream
    
    func makeUIView(context: Context) -> MTHKView {
        let view = MTHKView(frame: .zero)
        view.videoGravity = AVLayerVideoGravity.resizeAspectFill
        view.attachStream(stream)
        return view
    }
    
    func updateUIView(_ uiView: MTHKView, context: Context) {
        // No update needed
    }
}
