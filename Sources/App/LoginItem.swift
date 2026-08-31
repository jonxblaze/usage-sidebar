import Foundation
import ServiceManagement

enum LoginItem {
    private static let didAskKey = "UsageSidebar.didEnableLoginItem"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func enableOnFirstLaunch() {
        guard UserDefaults.standard.object(forKey: didAskKey) == nil else { return }
        UserDefaults.standard.set(true, forKey: didAskKey)
        try? SMAppService.mainApp.register()
    }
}
