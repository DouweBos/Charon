// TreemapLayoutTests.swift
// CharonKitTests

import CoreGraphics
import Testing
@testable import CharonKit

struct TreemapLayoutTests {

    private func sampleTree() -> DiskTree {
        var tree = DiskTree(rootPath: "/data", displayRootPath: "/")
        let users = tree.addNode(name: "Users", parent: DiskTree.root, kind: .directory)
        let me = tree.addNode(name: "me", parent: users, kind: .directory)
        tree.accumulate(into: me, size: 700, privateSize: 700, items: 1)
        let library = tree.addNode(name: "Library", parent: DiskTree.root, kind: .directory)
        let caches = tree.addNode(name: "Caches", parent: library, kind: .directory)
        tree.accumulate(into: caches, size: 200, privateSize: 200, items: 1)
        tree.accumulate(into: library, size: 50, privateSize: 50, items: 1)
        tree.accumulate(into: DiskTree.root, size: 50, privateSize: 50, items: 1)
        return tree
    }

    @Test func topLevelTilesMatchChildrenAndExtras() {
        let tree = sampleTree()
        let tiles = TreemapLayout.tiles(
            for: tree, focus: DiskTree.root, in: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: TreemapConfiguration(maxDepth: 1), unaccountedBytes: 100
        )
        #expect(tiles.map(\.title) == ["Users/me", "Library", "System & other", "Files"])
        #expect(tiles.allSatisfy { $0.depth == 1 && !$0.isContainer })
    }

    @Test func nestedTilesStayInsideTheirParent() {
        let tree = sampleTree()
        let tiles = TreemapLayout.tiles(for: tree, focus: DiskTree.root, in: CGRect(x: 0, y: 0, width: 800, height: 600))
        let library = tiles.first { $0.title == "Library" }!
        #expect(library.isContainer)
        let nested = tiles.filter { $0.depth == 2 && $0.colorIndex == library.colorIndex }
        #expect(!nested.isEmpty)
        #expect(nested.allSatisfy { library.rect.contains($0.rect) })
    }

    @Test func hitTestReturnsInnermostTile() {
        let tree = sampleTree()
        let tiles = TreemapLayout.tiles(for: tree, focus: DiskTree.root, in: CGRect(x: 0, y: 0, width: 800, height: 600))
        let caches = tiles.first { $0.title == "Caches" }!
        let hit = TreemapLayout.hitTest(tiles, at: CGPoint(x: caches.rect.midX, y: caches.rect.midY))
        #expect(hit?.title == "Caches")
    }

    @Test func detachSubtractsFromAncestors() {
        var tree = sampleTree()
        let caches = tree.node(atDisplayPath: "/Library/Caches")!
        tree.detach(caches)
        #expect(tree.node(atDisplayPath: "/Library/Caches") == nil)
        #expect(tree.size(tree.node(atDisplayPath: "/Library")!) == 50)
        #expect(tree.size(DiskTree.root) == 800)
    }
}
