// Cleanup/CleanMeasurer.swift
// CharonKit
//
// Sizes what a clean category would remove. Scans each root once and reads child sizes from the tree.

import Darwin
import Foundation

public struct CleanItem: Sendable, Hashable, Identifiable {
    public var url: URL
    public var bytes: Int64
    /// Extra context shown under the name, e.g. "feature/login · Merged into main".
    public var detail: String?
    public var id: String { url.path }

    public init(url: URL, bytes: Int64, detail: String? = nil) {
        self.url = url
        self.bytes = bytes
        self.detail = detail
    }
}

public struct CleanMeasurer: Sendable {
    public var resolver: CleanResolver

    public init(resolver: CleanResolver = CleanResolver()) {
        self.resolver = resolver
    }

    /// Items for the category, largest first.
    public func measure(_ category: CleanCategory) async throws -> [CleanItem] {
        var items: [CleanItem] = []
        switch category.mode {
        case .gitWorktrees:
            break
        case .itself, .emptyTrash:
            for url in category.paths.flatMap(resolver.matches) {
                items.append(CleanItem(url: url, bytes: try await Self.size(of: url)))
            }
        case .contents:
            let excluded = Set(category.excludes.map(resolver.expand))
            for root in category.paths.flatMap(resolver.matches) {
                let tree = try await Self.scan(root)
                for child in tree.children(DiskTree.root) where !excluded.contains(tree.realPath(child)) {
                    items.append(CleanItem(url: URL(fileURLWithPath: tree.realPath(child)), bytes: tree.size(child)))
                }
                // Files below the scan's node threshold aren't nodes; stat them directly.
                let known = Set(tree.children(DiskTree.root).map { tree.name($0) })
                for url in resolver.contents(of: root, excludes: category.excludes) where !known.contains(url.lastPathComponent) {
                    items.append(CleanItem(url: url, bytes: Self.allocatedSize(url)))
                }
            }
        }
        return items.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
    }

    public static func size(of url: URL) async throws -> Int64 {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return 0 }
        guard info.st_mode & S_IFMT == S_IFDIR else { return Int64(info.st_blocks) * 512 }
        return try await scan(url).size(DiskTree.root)
    }

    static func scan(_ url: URL) async throws -> DiskTree {
        var last: DiskTree?
        let options = ScanOptions(snapshotInterval: .seconds(60))
        for try await update in DiskScanner(options: options).scan(root: url) {
            last = update.tree
        }
        return last ?? DiskTree(rootPath: url.path, displayRootPath: url.path)
    }

    static func allocatedSize(_ url: URL) -> Int64 {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return 0 }
        return Int64(info.st_blocks) * 512
    }
}
