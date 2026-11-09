// Cleanup/TrashPolicy.swift
// CharonKit
//
// What may go to the Trash. Looser than Offload (anything the user owns inside a normal folder is fine)
// but never system locations, container roots, or offloaded symlinks. Your own items in temp folders are fine.

import Foundation

public struct TrashPolicy: Sendable {
    public var homeDirectory: URL
    public var offloadedPaths: Set<String>
    public var userID: uid_t
    /// Owner of the item at a path, nil when it can't be read.
    public var owner: @Sendable (String) -> uid_t?

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        offloadedPaths: Set<String> = [],
        userID: uid_t = getuid(),
        owner: @escaping @Sendable (String) -> uid_t? = TrashPolicy.lstatOwner
    ) {
        self.homeDirectory = homeDirectory
        self.offloadedPaths = offloadedPaths
        self.userID = userID
        self.owner = owner
    }

    public static func lstatOwner(_ path: String) -> uid_t? {
        var info = stat()
        return lstat(path, &info) == 0 ? info.st_uid : nil
    }

    static let protectedHomeItems = ["Library/Keychains", "Library/Application Support/Charon", "Library/Preferences"]

    /// Nil when `path` may be moved to the Trash, otherwise the reason it can't.
    public func refusal(for path: String) -> String? {
        let path = Self.privatePath(OffloadPreflight.userFacingPath(path))
        let home = homeDirectory.standardizedFileURL.path
        func within(_ root: String) -> Bool { path == root || path.hasPrefix(root + "/") }

        if let refusal = locationRefusal(path) { return refusal }
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
        if let inside = offloadedPaths.first(where: { $0.hasPrefix(path + "/") }) {
            return "It contains \((inside as NSString).lastPathComponent), which is offloaded. Move that back first."
        }
        return nil
    }

    /// Temp folders, external disks and system locations, which each have their own rule.
    private func locationRefusal(_ path: String) -> String? {
        let components = path.split(separator: "/")
        if let root = Self.tempRoot(containing: path) {
            if path == root { return "This folder must stay. Remove things inside it instead." }
            return owner(path) == userID ? nil : "It belongs to macOS or another user."
        }
        // Items on external disks live under /Volumes/<disk>/…; only the disk roots themselves are off limits.
        if components.first == "Volumes" { return components.count <= 2 ? "That's a whole disk." : nil }
        func within(_ root: String) -> Bool { path == root || path.hasPrefix(root + "/") }
        if OffloadPreflight.systemRoots.contains(where: within), !OffloadPreflight.systemExceptions.contains(where: within) {
            return "It's a macOS system location."
        }
        return nil
    }

    /// `/tmp` and `/var` are symlinks into `/private`; compare against the real location.
    static func privatePath(_ path: String) -> String {
        ["/tmp", "/var"].contains { path == $0 || path.hasPrefix($0 + "/") } ? "/private" + path : path
    }

    /// `/private/tmp` or a per-user `/private/var/folders/xx/yyyy/T` that holds `path`.
    static func tempRoot(containing path: String) -> String? {
        if path == "/private/tmp" || path.hasPrefix("/private/tmp/") { return "/private/tmp" }
        let parts = path.split(separator: "/")
        guard parts.count >= 6, parts.prefix(3).elementsEqual(["private", "var", "folders"]), parts[5] == "T" else { return nil }
        return "/" + parts.prefix(6).joined(separator: "/")
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
