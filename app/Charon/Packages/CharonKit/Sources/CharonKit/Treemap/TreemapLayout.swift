// Treemap/TreemapLayout.swift
// CharonKit
//
// Nested treemap over a DiskTree: flat list of tiles, parents before children, ready to draw and hit-test.

import CoreGraphics

public struct TreemapTile: Sendable, Hashable, Identifiable {
    public enum Content: Sendable, Hashable {
        case node(DiskTree.NodeID)
        /// Files too small to be their own node, directly inside `parent`.
        case looseFiles(parent: DiskTree.NodeID)
        /// Tail of tiny siblings merged into one tile.
        case others(parent: DiskTree.NodeID, count: Int)
        /// Used space the scan can't see: snapshots, purgeable space, the system volume.
        case unaccounted
    }

    public var id: Int
    public var content: Content
    public var title: String
    public var size: Int64
    public var rect: CGRect
    /// 1 for direct children of the focused node.
    public var depth: Int
    /// Index of the depth-1 ancestor, so a branch keeps one hue.
    public var colorIndex: Int
    /// Has nested tiles drawn inside it (under a header strip).
    public var isContainer: Bool

    public var node: DiskTree.NodeID? {
        if case .node(let id) = content { return id }
        return nil
    }
}

public struct TreemapEntry: Sendable, Hashable {
    public var content: TreemapTile.Content
    public var title: String
    public var size: Int64
    /// A directory with children, i.e. something to drill into.
    public var nestable: Bool
}

public struct TreemapConfiguration: Sendable, Hashable {
    public var maxDepth: Int
    public var gap: CGFloat
    public var headerHeight: CGFloat
    public var minNestedSize: CGSize
    public var maxItemsPerLevel: Int
    /// Tiles smaller than this can't show a name, so they're merged into one "Other" tile.
    public var minLabeledSize: CGSize

    public init(
        maxDepth: Int = 3, gap: CGFloat = 4, headerHeight: CGFloat = 22,
        minNestedSize: CGSize = CGSize(width: 100, height: 70), maxItemsPerLevel: Int = 40,
        minLabeledSize: CGSize = CGSize(width: 56, height: 30)
    ) {
        self.minLabeledSize = minLabeledSize
        self.maxDepth = maxDepth
        self.gap = gap
        self.headerHeight = headerHeight
        self.minNestedSize = minNestedSize
        self.maxItemsPerLevel = maxItemsPerLevel
    }
}

public enum TreemapLayout {

    /// - Parameter unaccountedBytes: extra "System & other" tile at the top level (volume root only).
    public static func tiles(
        for tree: DiskTree, focus: DiskTree.NodeID, in rect: CGRect,
        configuration: TreemapConfiguration = TreemapConfiguration(), unaccountedBytes: Int64 = 0
    ) -> [TreemapTile] {
        var tiles: [TreemapTile] = []
        layoutLevel(
            tree: tree, parent: focus, rect: rect, depth: 1, budget: 0, colorIndex: nil,
            configuration: configuration, unaccounted: unaccountedBytes, tiles: &tiles
        )
        return tiles
    }

    /// Innermost tile under `point`.
    public static func hitTest(_ tiles: [TreemapTile], at point: CGPoint) -> TreemapTile? {
        tiles.last { $0.rect.contains(point) }
    }

    /// One level of the map, largest first. The index doubles as the color index, so lists can match the map.
    public static func entries(
        for tree: DiskTree, parent: DiskTree.NodeID, unaccountedBytes: Int64 = 0,
        limit: Int = TreemapConfiguration().maxItemsPerLevel
    ) -> [TreemapEntry] {
        items(tree: tree, parent: parent, unaccounted: unaccountedBytes, limit: limit)
    }

    private typealias Item = TreemapEntry

    private static func items(
        tree: DiskTree, parent: DiskTree.NodeID, unaccounted: Int64, limit: Int
    ) -> [Item] {
        var items: [Item] = tree.sortedChildren(parent).compactMap { child in
            guard tree.size(child) > 0 else { return nil }
            let chain = tree.collapsedChain(from: child)
            let target = chain[chain.count - 1]
            return Item(
                content: .node(target), title: tree.collapsedName(chain), size: tree.size(child),
                nestable: tree.isDirectory(target) && !tree.children(target).isEmpty
            )
        }
        if items.count > limit {
            let tail = items[limit...]
            let tailSize = tail.reduce(Int64(0)) { $0 + $1.size }
            items = Array(items[..<limit])
            items.append(Item(content: .others(parent: parent, count: tail.count), title: "Other", size: tailSize, nestable: false))
        }
        let loose = tree.looseFilesSize(parent)
        if loose > 0 {
            items.append(Item(content: .looseFiles(parent: parent), title: "Files", size: loose, nestable: false))
        }
        if unaccounted > 0 {
            items.append(Item(content: .unaccounted, title: "System & other", size: unaccounted, nestable: false))
        }
        return items.sorted { $0.size > $1.size }
    }

    /// Folds tiles too small to label into a single "Other" tile, then lays the level out again.
    private static func mergingUnlabeled(
        _ items: [Item], rects: [CGRect], parent: DiskTree.NodeID, in rect: CGRect, configuration: TreemapConfiguration
    ) -> ([Item], [CGRect]) {
        let minimum = configuration.minLabeledSize
        let small = Set(items.indices.filter { index in
            let tile = rects[index].insetBy(dx: configuration.gap / 2, dy: configuration.gap / 2)
            return items[index].content != .unaccounted && (tile.width < minimum.width || tile.height < minimum.height)
        })
        guard small.count >= 2 else { return (items, rects) }

        var kept = items.indices.filter { !small.contains($0) }.map { items[$0] }
        let merged = small.map { items[$0] }
        let count = merged.reduce(0) { total, item in
            if case .others(_, let inner) = item.content { return total + inner }
            return total + 1
        }
        kept.append(Item(
            content: .others(parent: parent, count: count), title: "Other",
            size: merged.reduce(Int64(0)) { $0 + $1.size }, nestable: false
        ))
        kept.sort { $0.size > $1.size }
        return (kept, SquarifiedLayout.layout(weights: kept.map { Double($0.size) }, in: rect))
    }

    // swiftlint:disable:next function_parameter_count
    private static func layoutLevel(
        tree: DiskTree, parent: DiskTree.NodeID, rect: CGRect, depth: Int, budget: Int, colorIndex: Int?,
        configuration: TreemapConfiguration, unaccounted: Int64, tiles: inout [TreemapTile]
    ) {
        var levelItems = items(tree: tree, parent: parent, unaccounted: unaccounted, limit: configuration.maxItemsPerLevel)
        var rects = SquarifiedLayout.layout(weights: levelItems.map { Double($0.size) }, in: rect)
        (levelItems, rects) = mergingUnlabeled(levelItems, rects: rects, parent: parent, in: rect, configuration: configuration)
        // A level where one folder holds nearly everything ("Users" → "douwe") tells you nothing new,
        // so it doesn't use up a level of the depth budget.
        let total = levelItems.reduce(Int64(0)) { $0 + $1.size }
        let dominated = (levelItems.first?.size ?? 0) * 100 >= total * 85
        let spent = budget + (dominated ? 0 : 1)
        let half = configuration.gap / 2

        for (index, (item, itemRect)) in zip(levelItems, rects).enumerated() {
            let inset = itemRect.insetBy(dx: half, dy: half)
            guard inset.width >= 2, inset.height >= 2 else { continue }
            let color = colorIndex ?? index
            let canNest = item.nestable && spent < configuration.maxDepth
                && inset.width >= configuration.minNestedSize.width && inset.height >= configuration.minNestedSize.height
            tiles.append(TreemapTile(
                id: tiles.count, content: item.content, title: item.title, size: item.size,
                rect: inset, depth: depth, colorIndex: color, isContainer: canNest
            ))
            guard canNest, case .node(let target) = item.content else { continue }
            let inner = CGRect(
                x: inset.minX + half, y: inset.minY + configuration.headerHeight,
                width: inset.width - configuration.gap, height: inset.height - configuration.headerHeight - half
            )
            layoutLevel(
                tree: tree, parent: target, rect: inner, depth: depth + 1, budget: spent, colorIndex: color,
                configuration: configuration, unaccounted: 0, tiles: &tiles
            )
        }
    }
}
