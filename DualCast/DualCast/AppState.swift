import Foundation
import Combine
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var twitchStreamKey: String {
        didSet { UserDefaults.standard.set(twitchStreamKey, forKey: "twitchStreamKey") }
    }
    @Published var rtmpURL: String {
        didSet { UserDefaults.standard.set(rtmpURL, forKey: "rtmpURL") }
    }
    @Published var saveLocalRecording: Bool {
        didSet { UserDefaults.standard.set(saveLocalRecording, forKey: "saveLocalRecording") }
    }
    
    init() {
        self.twitchStreamKey = UserDefaults.standard.string(forKey: "twitchStreamKey") ?? ""
        self.rtmpURL = UserDefaults.standard.string(forKey: "rtmpURL") ?? "rtmp://live.twitch.tv/app/"
        self.saveLocalRecording = UserDefaults.standard.bool(forKey: "saveLocalRecording")
    }
}
