//
//  DualCastApp.swift
//  DualCast
//

import SwiftUI

@main
struct DualCastApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            StreamView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
    }
}
