import Foundation
import ServiceManagement

enum StartAtLoginManager {
    static func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } else {
            throw NSError(
                domain: "ASIAIRSync",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Start at login is supported on macOS 13+"]
            )
        }
    }
}
