import Foundation

enum SyncPhase: String, Codable {
    case notConfigured
    case paused
    case syncing
    case idle
    case error
}

struct SyncSettings: Codable {
    var host: String
    var shareName: String
    var destinationPath: String
    var syncIntervalSeconds: Int
    var deleteRemovedFiles: Bool

    static let defaults = SyncSettings(
        host: "",
        shareName: "EMMC Images",
        destinationPath: "",
        syncIntervalSeconds: 10,
        deleteRemovedFiles: true
    )

    var isConfigured: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var normalized: SyncSettings {
        SyncSettings(
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            shareName: shareName.trimmingCharacters(in: .whitespacesAndNewlines),
            destinationPath: destinationPath.trimmingCharacters(in: .whitespacesAndNewlines),
            syncIntervalSeconds: max(syncIntervalSeconds, 1),
            deleteRemovedFiles: deleteRemovedFiles
        )
    }
}

struct SyncRuntimeStatus {
    var phase: SyncPhase = .notConfigured
    var message: String = "Not configured"
    var progressPercent: Double = 0
    var transferSpeed: String?
    var filesLeftToDownload: Int = 0
    var localFitsCount: Int = 0
    var remoteFitsCount: Int = 0
    var lastSyncedAt: Date?
    var currentFile: String?

    static let initial = SyncRuntimeStatus()
}
