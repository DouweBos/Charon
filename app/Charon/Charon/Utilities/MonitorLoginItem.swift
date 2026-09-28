// Utilities/MonitorLoginItem.swift
// Charon
//
// Registers the embedded menu bar monitor as a login item.

import CharonKit
import Foundation
import os
import ServiceManagement

enum MonitorLoginItem {
    private static var service: SMAppService { SMAppService.loginItem(identifier: MonitorSettings.monitorBundleID) }

    static var isEnabled: Bool { service.status == .enabled }
    static var needsApproval: Bool { service.status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try service.register() } else { try service.unregister() }
    }

    /// Turns the monitor on once, the first time Charon runs. After that the Settings toggle decides.
    static func enableOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: AppSettings.monitorEnabledByDefault) else { return }
        defaults.set(true, forKey: AppSettings.monitorEnabledByDefault)
        do {
            try setEnabled(true)
        } catch {
            Logger.volumes.error("Couldn't enable the menu bar monitor: \(error.localizedDescription, privacy: .public)")
        }
        Logger.volumes.info("Menu bar monitor status: \(String(describing: service.status), privacy: .public)")
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
