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
    static let driveVolumeID = "offload.driveVolumeID"
    static let driveFolder = "offload.driveFolder"
    static let recentFolders = "scan.recentFolders"
    static let excludedPaths = "scan.excludedPaths"
    static let accessPromptShown = "onboarding.accessPromptShown"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: MonitorSettings.defaults)
        UserDefaults.standard.register(defaults: [
            largeFileThresholdMB: 50,
            measurePrivateSize: false,
            rememberScans: true,
            treemapDepth: 2,
            showStats: true,
            driveFolder: "Charon"
        ])
    }

    static var scanOptions: ScanOptions {
        let defaults = UserDefaults.standard
        var options = ScanOptions(
            largeFileThreshold: Int64(max(defaults.integer(forKey: largeFileThresholdMB), 1)) * 1_000_000,
            measurePrivateSize: defaults.bool(forKey: measurePrivateSize)
        )
        // The boot disk is scanned through the Data volume, so match both spellings of each path.
        let excluded = defaults.stringArray(forKey: excludedPaths) ?? []
        options.excludedPaths = Set(excluded + excluded.map { "/System/Volumes/Data" + $0 })
        return options
    }

    static var driveFolderName: String {
        let name = UserDefaults.standard.string(forKey: driveFolder)?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty || name.contains("/") ? "Charon" : name
    }
}
