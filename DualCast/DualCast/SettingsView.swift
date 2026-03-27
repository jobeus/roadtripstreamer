import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var routeTracker: RouteTracker
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Stream Settings")) {
                    SecureField("Twitch Stream Key", text: $appState.twitchStreamKey)
                    TextField("RTMP URL", text: $appState.rtmpURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
                
                Section(header: Text("Recording")) {
                    Toggle("Save Local Copy (MP4)", isOn: $appState.saveLocalRecording)
                }
                
                Section(header: Text("Map")) {
                    Button(role: .destructive, action: {
                        routeTracker.clearRoute()
                        dismiss()
                    }) {
                        Text("Clear Route Data")
                    }
                }
                
                Section(header: Text("Instructions")) {
                    Text("Enter your Twitch Stream Key to go live. The default RTMP URL is for Twitch's global ingestion server.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
}
