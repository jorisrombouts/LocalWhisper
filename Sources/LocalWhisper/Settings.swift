import Foundation
import ServiceManagement

enum Settings {
    static let cleanupEnabledKey = "cleanupEnabled"
    static var cleanupEnabled: Bool {
        UserDefaults.standard.object(forKey: cleanupEnabledKey) as? Bool ?? true
    }
    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
    }
}
