// Scanner/ScanComparison.swift
// CharonKit
//
// What changed between two scans of the same target, matched by display path.

import Foundation

public struct GrowthItem: Sendable, Hashable, Identifiable {
    public var path: String
    public var bytes: Int64
    /// Positive when the folder grew.
    public var delta: Int64
    public var isNew: Bool
    public var id: String { path }
}

public struct ScanComparison: Sendable {
    public let previous: DiskTree
    public let current: DiskTree
    public let previousDate: Date

    public init(previous: DiskTree, current: DiskTree, previousDate: Date) {
        self.previous = previous
        self.current = current
        self.previousDate = previousDate
    }

    /// Size change of the node at `path` in the current tree; nil when it didn't exist before.
    public func delta(atDisplayPath path: String) -> Int64? {
        guard let now = current.node(atDisplayPath: path) else { return nil }
        guard let before = previous.node(atDisplayPath: path) else { return nil }
        return current.size(now) - previous.size(before)
    }

    /// Folders that explain the most growth. Growth is attributed to the deepest folders that grew by at least
    /// `minimum`; a parent is listed too (with only its unexplained remainder) when its growth is spread thin.
    public func topGrowth(minimum: Int64 = 100_000_000, limit: Int = 20, maxDepth: Int = 12) -> [GrowthItem] {
        var items: [GrowthItem] = []
        collect(DiskTree.root, depth: 0, minimum: minimum, maxDepth: maxDepth, into: &items)
        return Array(items.sorted { $0.delta > $1.delta }.prefix(limit))
    }

    private func collect(_ node: DiskTree.NodeID, depth: Int, minimum: Int64, maxDepth: Int, into items: inout [GrowthItem]) {
        var explained: Int64 = 0
        if depth < maxDepth {
            for child in current.children(node) where current.isDirectory(child) {
                let growth = growthOf(child)
                guard growth >= minimum else { continue }
                explained += growth
                collect(child, depth: depth + 1, minimum: minimum, maxDepth: maxDepth, into: &items)
            }
        }
        let remainder = growthOf(node) - explained
        guard node != DiskTree.root, remainder >= minimum else { return }
        let path = current.displayPath(node)
        items.append(GrowthItem(
            path: path, bytes: current.size(node), delta: remainder, isNew: previous.node(atDisplayPath: path) == nil
        ))
    }

    private func growthOf(_ node: DiskTree.NodeID) -> Int64 {
        let path = current.displayPath(node)
        let before = previous.node(atDisplayPath: path).map(previous.size) ?? 0
        return current.size(node) - before
    }
}
