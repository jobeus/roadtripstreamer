import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Stream Settings")) {
                    SecureField("Twitch Stream Key", text: $appState.twitchStreamKey)
                    TextField("RTMP URL", text: $appState.rtmpURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    TextField("Twitch Channel Name", text: $appState.twitchChannelName)
                        .autocapitalization(.none)
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
