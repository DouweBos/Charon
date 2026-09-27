// Offload/OffloadSuggester.swift
// CharonKit
//
// Picks the biggest folders in the home directory that pass every offload rule, without overlaps.

import Darwin
import Foundation

public struct OffloadSuggestion: Sendable, Hashable, Identifiable {
    public var path: String
    public var bytes: Int64
    public var lastModified: Date?
    public var id: String { path }
}

public struct OffloadSuggester: Sendable {
    public var preflight: OffloadPreflight
    public var minimumBytes: Int64
    public var maxDepth: Int

    public init(preflight: OffloadPreflight = OffloadPreflight(), minimumBytes: Int64 = 1_000_000_000, maxDepth: Int = 4) {
        self.preflight = preflight
        self.minimumBytes = minimumBytes
        self.maxDepth = maxDepth
    }

    public func suggestions(in tree: DiskTree, existing: [OffloadRecord] = [], limit: Int = 8) -> [OffloadSuggestion] {
        let home = preflight.homeDirectory.standardizedFileURL.path
        guard let homeNode = tree.node(atDisplayPath: home) else { return [] }
        let offloaded = existing.map(\.originalPath)

        var candidates: [DiskTree.NodeID] = []
        var stack: [(DiskTree.NodeID, Int)] = [(homeNode, 0)]
        while let (node, depth) = stack.popLast() {
            for child in tree.children(node) where tree.isDirectory(child) && tree.size(child) >= minimumBytes {
                candidates.append(child)
                if depth + 1 < maxDepth { stack.append((child, depth + 1)) }
            }
        }

        var picked: [OffloadSuggestion] = []
        for node in candidates.sorted(by: { tree.size($0) > tree.size($1) }) {
            let path = tree.displayPath(node)
            let overlaps = (picked.map(\.path) + offloaded).contains { other in
                path == other || path.hasPrefix(other + "/") || other.hasPrefix(path + "/")
            }
            guard !overlaps, preflight.pathRules(path).isEmpty else { continue }
            picked.append(OffloadSuggestion(path: path, bytes: tree.size(node), lastModified: Self.modified(path)))
            if picked.count == limit { break }
        }
        return picked
    }

    static func modified(_ path: String) -> Date? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
    }
}
