import SwiftUI

@main
struct ASIAIRSyncApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("ASIAIR Sync", systemImage: model.menuBarSymbolName) {
            MenuBarContentView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
