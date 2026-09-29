// Utilities/FileRemoval.swift
// Charon
//
// Moves items to the Trash, or deletes them outright when that's turned on in Settings.

import AppKit
import CharonKit
import Foundation

enum FileRemoval {
    static var deletesPermanently: Bool {
        UserDefaults.standard.bool(forKey: AppSettings.deletePermanently)
    }

    /// `onProgress` gets bytes deleted so far; the Trash moves items whole, so it's only called for permanent deletes.
    static func remove(
        _ urls: [URL], permanently: Bool, onProgress: @escaping @Sendable (Int64) -> Void = { _ in }
    ) async throws {
        guard permanently else {
            _ = try await NSWorkspace.shared.recycle(urls)
            return
        }
        try await Task.detached(priority: .userInitiated) {
            var base: Int64 = 0
            for url in urls {
                var deleted: Int64 = 0
                try FileDeleter.delete(url) { bytes in
                    deleted = bytes
                    onProgress(base + bytes)
                }
                base += deleted
            }
        }.value
    }
}
