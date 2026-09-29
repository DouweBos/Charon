// Monitor/MonitorSettings.swift
// CharonKit
//
// Settings the menu bar monitor reads from Charon's defaults domain, shared by both apps.

import Foundation

public enum MonitorSettings {
    public static let suiteName = "dev.houwert.charon"
    public static let monitorBundleID = "dev.houwert.charon.monitor"
    public static let appBundleID = "dev.houwert.charon"

    public static let lowGigabytes = "monitor.lowGigabytes"
    public static let lowPercent = "monitor.lowPercent"
    public static let criticalGigabytes = "monitor.criticalGigabytes"
    public static let showFreeSpace = "monitor.showFreeSpace"
    public static let notifyDisconnected = "monitor.notifyDisconnected"

    public static var defaults: [String: Any] {
        [lowGigabytes: 20, lowPercent: 5, criticalGigabytes: 5, showFreeSpace: true, notifyDisconnected: true]
    }

    public static func policy(from store: UserDefaults) -> LowSpacePolicy {
        LowSpacePolicy(
            lowBytes: Int64(store.integer(forKey: lowGigabytes)) * 1_000_000_000,
            lowFraction: Double(store.integer(forKey: lowPercent)) / 100,
            criticalBytes: Int64(store.integer(forKey: criticalGigabytes)) * 1_000_000_000
        )
    }
}
