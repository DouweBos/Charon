// Cleanup/TrashPolicy.swift
// CharonKit
//
// What may go to the Trash. Looser than Offload (anything the user owns inside a normal folder is fine)
// but never system locations, container roots, or offloaded symlinks.

import Foundation

public struct TrashPolicy: Sendable {
    public var homeDirectory: URL
    public var offloadedPaths: Set<String>

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser, offloadedPaths: Set<String> = []) {
        self.homeDirectory = homeDirectory
        self.offloadedPaths = offloadedPaths
    }

    static let protectedHomeItems = ["Library/Keychains", "Library/Application Support/Charon", "Library/Preferences"]

    /// Nil when `path` may be moved to the Trash, otherwise the reason it can't.
    public func refusal(for path: String) -> String? {
        let path = OffloadPreflight.userFacingPath(path)
        let home = homeDirectory.standardizedFileURL.path
        func within(_ root: String) -> Bool { path == root || path.hasPrefix(root + "/") }

        if OffloadPreflight.systemRoots.contains(where: within), !OffloadPreflight.systemExceptions.contains(where: within) {
            return "It's a macOS system location."
        }
        let exact = OffloadPreflight.exactRoots + OffloadPreflight.homeExactRoots.map { $0.isEmpty ? home : home + "/" + $0 }
        if exact.contains(path) {
            return "This folder must stay. Remove things inside it instead."
        }
        if Self.protectedHomeItems.map({ home + "/" + $0 }).contains(where: within) {
            return "macOS or Charon depends on it."
        }
        if path.split(separator: "/").dropLast().contains(where: { $0.hasSuffix(".app") }) {
            return "It's inside an app. Remove the whole app instead."
        }
        if offloadedPaths.contains(path) || offloadedPaths.contains(where: { path.hasPrefix($0 + "/") }) {
            return "It's offloaded. Move it back or forget it first."
        }
        return nil
    }
}

/// Items gathered for removal. Keeps the set minimal: no item is inside another.
public struct CollectorSet: Sendable, Hashable {
    public struct Item: Sendable, Hashable, Identifiable {
        public var path: String
        public var bytes: Int64
        public var isDirectory: Bool
        public var id: String { path }

        public init(path: String, bytes: Int64, isDirectory: Bool) {
            self.path = path
            self.bytes = bytes
            self.isDirectory = isDirectory
        }
    }

    public private(set) var items: [Item] = []

    public init() {}

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    public func contains(_ path: String) -> Bool {
        items.contains { $0.path == path || path.hasPrefix($0.path + "/") }
    }

    /// Adding a folder absorbs anything already collected inside it; adding something inside a collected folder is a no-op.
    public mutating func add(_ item: Item) {
        guard !contains(item.path) else { return }
        items.removeAll { $0.path.hasPrefix(item.path + "/") }
        items.append(item)
        items.sort { $0.bytes > $1.bytes }
    }

    public mutating func remove(_ path: String) {
        items.removeAll { $0.path == path }
    }

    public mutating func removeAll() {
        items.removeAll()
    }
}
