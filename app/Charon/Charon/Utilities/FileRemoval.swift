// Utilities/FileRemoval.swift
// Charon
//
// Moves items to the Trash, or deletes them outright when that's turned on in Settings.

import AppKit
import Foundation

enum FileRemoval {
    static var deletesPermanently: Bool {
        UserDefaults.standard.bool(forKey: AppSettings.deletePermanently)
    }

    static func remove(_ urls: [URL], permanently: Bool) async throws {
        guard permanently else {
            _ = try await NSWorkspace.shared.recycle(urls)
            return
        }
        try await Task.detached(priority: .userInitiated) {
            for url in urls { try FileManager.default.removeItem(at: url) }
        }.value
    }
}
