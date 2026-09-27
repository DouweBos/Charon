// Scanner/DiskTree.swift
// CharonKit
//
// Immutable snapshot of a scan. Struct-of-arrays so millions of nodes stay cheap to copy between threads.

import Foundation

public struct DiskTree: Sendable {
    public typealias NodeID = Int32

    public enum Kind: UInt8, Sendable {
        case directory
        case file
    }

    /// Real filesystem path of the root (e.g. `/System/Volumes/Data`).
    public let rootPath: String
    /// Path shown to the user for the root (e.g. `/`).
    public let displayRootPath: String

    var names: [String]
    var parents: [NodeID]
    var childLists: [[NodeID]]
    var sizes: [Int64]
    var privateSizes: [Int64]
    var itemCounts: [Int64]
    var kinds: [Kind]

    public static let root: NodeID = 0

    public init(rootPath: String, displayRootPath: String) {
        self.rootPath = rootPath
        self.displayRootPath = displayRootPath
        names = [displayRootPath]
        parents = [-1]
        childLists = [[]]
        sizes = [0]
        privateSizes = [0]
        itemCounts = [0]
        kinds = [.directory]
    }

    init(
        rootPath: String, displayRootPath: String, names: [String], parents: [NodeID], childLists: [[NodeID]],
        sizes: [Int64], privateSizes: [Int64], itemCounts: [Int64], kinds: [Kind]
    ) {
        self.rootPath = rootPath
        self.displayRootPath = displayRootPath
        self.names = names
        self.parents = parents
        self.childLists = childLists
        self.sizes = sizes
        self.privateSizes = privateSizes
        self.itemCounts = itemCounts
        self.kinds = kinds
    }

    public var nodeCount: Int { names.count }

    public func name(_ id: NodeID) -> String { names[Int(id)] }
    public func size(_ id: NodeID) -> Int64 { sizes[Int(id)] }
    /// Bytes not shared with APFS clones: what deleting or ferrying this would actually free.
    public func privateSize(_ id: NodeID) -> Int64 { privateSizes[Int(id)] }
    public func itemCount(_ id: NodeID) -> Int64 { itemCounts[Int(id)] }
    public func kind(_ id: NodeID) -> Kind { kinds[Int(id)] }
    public func isDirectory(_ id: NodeID) -> Bool { kinds[Int(id)] == .directory }
    public func children(_ id: NodeID) -> [NodeID] { childLists[Int(id)] }

    public func parent(_ id: NodeID) -> NodeID? {
        let parent = parents[Int(id)]
        return parent < 0 ? nil : parent
    }

    public func sortedChildren(_ id: NodeID) -> [NodeID] {
        childLists[Int(id)].sorted { sizes[Int($0)] > sizes[Int($1)] }
    }

    /// Bytes of files directly inside `id` that are too small to be their own node.
    public func looseFilesSize(_ id: NodeID) -> Int64 {
        let childTotal = childLists[Int(id)].reduce(Int64(0)) { $0 + sizes[Int($1)] }
        return max(sizes[Int(id)] - childTotal, 0)
    }

    /// Root first, `id` last.
    public func lineage(_ id: NodeID) -> [NodeID] {
        var chain: [NodeID] = []
        var current: NodeID? = id
        while let node = current {
            chain.append(node)
            current = parent(node)
        }
        return chain.reversed()
    }

    private func components(_ id: NodeID) -> [String] {
        lineage(id).dropFirst().map { names[Int($0)] }
    }

    public func realPath(_ id: NodeID) -> String {
        Self.join(rootPath, components(id))
    }

    public func displayPath(_ id: NodeID) -> String {
        Self.join(displayRootPath, components(id))
    }

    public func node(atDisplayPath path: String) -> NodeID? {
        guard path.hasPrefix(displayRootPath) else { return nil }
        let rest = path.dropFirst(displayRootPath.count).split(separator: "/")
        var current = Self.root
        for component in rest {
            guard let next = childLists[Int(current)].first(where: { names[Int($0)] == component }) else { return nil }
            current = next
        }
        return current
    }

    /// Follows single-directory chains ("opt" → "opt/homebrew") so the UI doesn't show a lone wrapper folder.
    public func collapsedChain(from id: NodeID) -> [NodeID] {
        var chain = [id]
        var current = id
        while let only = childLists[Int(current)].first, childLists[Int(current)].count == 1,
              kinds[Int(only)] == .directory, looseFilesSize(current) * 100 <= max(sizes[Int(current)], 1) {
            chain.append(only)
            current = only
        }
        return chain
    }

    public func collapsedName(_ chain: [NodeID]) -> String {
        chain.map { names[Int($0)] }.joined(separator: "/")
    }

    static func join(_ base: String, _ components: [String]) -> String {
        guard !components.isEmpty else { return base }
        let prefix = base.hasSuffix("/") ? base : base + "/"
        return prefix + components.joined(separator: "/")
    }
}

// MARK: - Editing

extension DiskTree {
    /// Removes a subtree and subtracts its bytes from its ancestors, e.g. after it was ferried away.
    public mutating func detach(_ id: NodeID) {
        guard let parent = parent(id) else { return }
        accumulate(into: parent, size: -sizes[Int(id)], privateSize: -privateSizes[Int(id)], items: -itemCounts[Int(id)])
        childLists[Int(parent)].removeAll { $0 == id }
    }
}

// MARK: - Mutation (scanner only)

extension DiskTree {
    mutating func addNode(name: String, parent: NodeID, kind: Kind, size: Int64 = 0, privateSize: Int64 = 0) -> NodeID {
        let id = NodeID(names.count)
        names.append(name)
        parents.append(parent)
        childLists.append([])
        sizes.append(size)
        privateSizes.append(privateSize)
        itemCounts.append(kind == .file ? 1 : 0)
        kinds.append(kind)
        childLists[Int(parent)].append(id)
        return id
    }

    /// Adds bytes to `id` and every ancestor, keeping cumulative sizes consistent at all times.
    mutating func accumulate(into id: NodeID, size: Int64, privateSize: Int64, items: Int64) {
        var current = id
        while current >= 0 {
            let index = Int(current)
            sizes[index] += size
            privateSizes[index] += privateSize
            itemCounts[index] += items
            current = parents[index]
        }
    }
}
