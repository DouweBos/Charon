// Utilities/MonitorLoginItem.swift
// Charon
//
// Registers the embedded menu bar monitor as a login item.

import CharonKit
import ServiceManagement

enum MonitorLoginItem {
    private static var service: SMAppService { SMAppService.loginItem(identifier: MonitorSettings.monitorBundleID) }

    static var isEnabled: Bool { service.status == .enabled }
    static var needsApproval: Bool { service.status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try service.register() } else { try service.unregister() }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
