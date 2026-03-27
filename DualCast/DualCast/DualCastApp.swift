//
//  DualCastApp.swift
//  DualCast
//

import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .landscapeRight
    }
}

@main
struct DualCastApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            StreamView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
    }
}
