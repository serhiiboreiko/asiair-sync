import SwiftUI
import Foundation

private enum WindowStateSanitizer {
    static func clearSavedWindowState() {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.serhiiboreiko.asiairsync"
        let savedStatePath = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Saved Application State/\(bundleId).savedState")
            .path
        try? FileManager.default.removeItem(atPath: savedStatePath)
    }
}

@main
struct ASIAIRSyncApp: App {
    @StateObject private var model = AppModel()

    init() {
        WindowStateSanitizer.clearSavedWindowState()
    }

    var body: some Scene {
        MenuBarExtra("ASIAIR Sync", systemImage: model.menuBarSymbolName) {
            MenuBarContentView(model: model)
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 380, height: 520)
        .windowResizability(.contentSize)
    }
}
