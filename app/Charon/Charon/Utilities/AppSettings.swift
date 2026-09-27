// Utilities/AppSettings.swift
// Charon
//
// UserDefaults keys and defaults. Documented in docs/settings.md.

import CharonKit
import Foundation

enum AppSettings {
    static let largeFileThresholdMB = "scan.largeFileThresholdMB"
    static let measurePrivateSize = "scan.measurePrivateSize"
    static let rememberScans = "scan.rememberResults"
    static let treemapDepth = "treemap.depth"
    static let showStats = "stats.visible"
    static let shoreVolumeID = "ferry.shoreVolumeID"
    static let shoreFolder = "ferry.shoreFolder"
    static let accessPromptShown = "onboarding.accessPromptShown"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            largeFileThresholdMB: 50,
            measurePrivateSize: false,
            rememberScans: true,
            treemapDepth: 2,
            showStats: true,
            shoreFolder: "Charon"
        ])
    }

    static var scanOptions: ScanOptions {
        let defaults = UserDefaults.standard
        return ScanOptions(
            largeFileThreshold: Int64(max(defaults.integer(forKey: largeFileThresholdMB), 1)) * 1_000_000,
            measurePrivateSize: defaults.bool(forKey: measurePrivateSize)
        )
    }

    static var shoreFolderName: String {
        let name = UserDefaults.standard.string(forKey: shoreFolder)?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty || name.contains("/") ? "Charon" : name
    }
}
