import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    private static let settingsKey = "asiair.sync.settings"
    private static let didAskStartAtLoginKey = "asiair.sync.didAskStartAtLogin"
    private static let settingsExpandedKey = "asiair.sync.settingsExpanded"

    @Published var settings: SyncSettings
    @Published var runtimeStatus: SyncRuntimeStatus
    @Published var showStartAtLoginPrompt = false
    @Published var startAtLoginFeedback: String?

    private let defaults = UserDefaults.standard
    private let syncEngine: SyncEngine
    private var cancellables = Set<AnyCancellable>()

    init() {
        let loadedSettings = Self.loadSettings(from: UserDefaults.standard, key: Self.settingsKey)
        self.settings = loadedSettings
        self.runtimeStatus = loadedSettings.isConfigured
            ? SyncRuntimeStatus(phase: .paused, message: "Paused", progressPercent: 0, transferSpeed: nil, filesLeftToDownload: 0, localFitsCount: 0, lastSyncedAt: nil, currentFile: nil)
            : .initial

        let engine = SyncEngine(initialSettings: loadedSettings)
        self.syncEngine = engine

        engine.onStatus = { [weak self] status in
            DispatchQueue.main.async {
                self?.runtimeStatus = status
            }
        }

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.syncEngine.stop()
            }
            .store(in: &cancellables)

        engine.updateSettings(loadedSettings)
        if loadedSettings.isConfigured {
            engine.setPaused(false)
        } else {
            engine.setPaused(true)
        }
    }

    var menuBarSymbolName: String {
        switch runtimeStatus.phase {
        case .notConfigured:
            return "gearshape"
        case .paused:
            return "pause.circle"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .idle:
            return "checkmark.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    var phaseLabel: String {
        switch runtimeStatus.phase {
        case .notConfigured:
            return "Not configured"
        case .paused:
            return "Paused"
        case .syncing:
            return "Syncing"
        case .idle:
            return "Idle"
        case .error:
            return "Error"
        }
    }

    var canApplySettings: Bool {
        settings.normalized.isConfigured
    }

    func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Select the local folder where FITS files will be synced"

        if panel.runModal() == .OK, let selectedPath = panel.url?.path {
            settings.destinationPath = selectedPath
        }
    }

    func applySettingsAndStart() {
        settings = settings.normalized
        persistSettings(settings)
        syncEngine.updateSettings(settings)

        guard settings.isConfigured else {
            return
        }

        syncEngine.setPaused(false)
    }

    func pauseOrResume() {
        switch runtimeStatus.phase {
        case .syncing, .idle:
            syncEngine.setPaused(true)
        case .paused, .error, .notConfigured:
            guard settings.normalized.isConfigured else {
                return
            }
            syncEngine.setPaused(false)
        }
    }

    func shutdown() {
        syncEngine.stop()
    }

    func maybePromptForStartAtLogin() {
        if defaults.bool(forKey: Self.didAskStartAtLoginKey) {
            return
        }
        showStartAtLoginPrompt = true
    }

    func handleStartAtLoginChoice(enable: Bool) {
        defaults.set(true, forKey: Self.didAskStartAtLoginKey)
        showStartAtLoginPrompt = false

        if enable {
            do {
                try StartAtLoginManager.setEnabled(true)
                startAtLoginFeedback = "Start at login enabled"
            } catch {
                startAtLoginFeedback = "Could not enable start at login: \(error.localizedDescription)"
            }
        } else {
            startAtLoginFeedback = "Start at login left disabled"
        }
    }

    func loadSettingsExpandedPreference() -> Bool {
        if let stored = defaults.object(forKey: Self.settingsExpandedKey) as? Bool {
            return stored
        }
        return isFirstOpen()
    }

    func saveSettingsExpandedPreference(_ expanded: Bool) {
        defaults.set(expanded, forKey: Self.settingsExpandedKey)
    }

    private func isFirstOpen() -> Bool {
        defaults.object(forKey: Self.didAskStartAtLoginKey) == nil
    }

    private func persistSettings(_ settings: SyncSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        defaults.set(data, forKey: Self.settingsKey)
    }

    private static func loadSettings(from defaults: UserDefaults, key: String) -> SyncSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(SyncSettings.self, from: data) else {
            return SyncSettings.defaults
        }

        return decoded
    }

    deinit {
        syncEngine.stop()
    }
}
