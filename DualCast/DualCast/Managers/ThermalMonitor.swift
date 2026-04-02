import Foundation
import SwiftUI
import Combine

@MainActor
class ThermalMonitor: ObservableObject {
    @Published var isCritical: Bool = false
    
    init() {
        checkThermalState()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    nonisolated @objc private func thermalStateChanged() {
        Task { @MainActor in
            self.checkThermalState()
        }
    }
    
    private func checkThermalState() {
        let state = ProcessInfo.processInfo.thermalState
        isCritical = (state == .serious || state == .critical)
    }
}
