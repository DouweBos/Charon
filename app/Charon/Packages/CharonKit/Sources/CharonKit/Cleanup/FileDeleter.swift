// Cleanup/FileDeleter.swift
// CharonKit
//
// Permanent deletion one file at a time, so a big folder can report progress instead of one long silent call.

import Foundation

public enum FileDeleter {
    /// `onProgress` gets the bytes deleted so far. Symlinks are removed, never followed.
    public static func delete(_ url: URL, onProgress: (Int64) -> Void = { _ in }) throws {
        var deleted: Int64 = 0
        try delete(url, deleted: &deleted, onProgress: onProgress)
    }

    private static let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey]

    private static func delete(_ url: URL, deleted: inout Int64, onProgress: (Int64) -> Void) throws {
        let values = try url.resourceValues(forKeys: Set(keys))
        if values.isDirectory == true, values.isSymbolicLink != true {
            let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys)
            for child in children { try delete(child, deleted: &deleted, onProgress: onProgress) }
        }
        try FileManager.default.removeItem(at: url)
        deleted += Int64(values.totalFileAllocatedSize ?? 0)
        onProgress(deleted)
    }
}
