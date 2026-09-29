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

    @Test func appBundlesAreOneTile() {
        var tree = DiskTree(rootPath: "/data", displayRootPath: "/")
        let app = tree.addNode(name: "Cinebench.app", parent: DiskTree.root, kind: .directory)
        let contents = tree.addNode(name: "Contents", parent: app, kind: .directory)
        let resources = tree.addNode(name: "Resources", parent: contents, kind: .directory)
        tree.accumulate(into: resources, size: 500, privateSize: 500, items: 1)
        let tiles = TreemapLayout.tiles(for: tree, focus: DiskTree.root, in: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(tiles.map(\.title) == ["Cinebench.app"])
        #expect(!tiles[0].isContainer)
        #expect(!tree.canOpen(app))
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

    @Test func hidingLeavesTheOriginalIntact() {
        let tree = sampleTree()
        let hidden = tree.hiding(displayPaths: ["/Library/Caches", "/missing"])
        #expect(hidden.node(atDisplayPath: "/Library/Caches") == nil)
        #expect(hidden.size(DiskTree.root) == 800)
        #expect(tree.node(atDisplayPath: "/Library/Caches") != nil)
        #expect(tree.size(DiskTree.root) == 1000)
    }

    @Test func largestFilesWalksTheSubtree() {
        var tree = sampleTree()
        let caches = tree.node(atDisplayPath: "/Library/Caches")!
        let big = tree.addNode(name: "big.bin", parent: caches, kind: .file, size: 90)
        let small = tree.addNode(name: "small.bin", parent: DiskTree.root, kind: .file, size: 10)
        #expect(tree.largestFiles(under: DiskTree.root, limit: 5) == [big, small])
        #expect(tree.largestFiles(under: caches, limit: 5) == [big])
        #expect(tree.largestFiles(under: DiskTree.root, limit: 1) == [big])
    }

    @Test func graftReplacesSubtreeAndFixesTotals() {
        var tree = sampleTree()
        let library = tree.node(atDisplayPath: "/Library")!
        var fresh = DiskTree(rootPath: "/data/Library", displayRootPath: "/Library")
        let fonts = fresh.addNode(name: "Fonts", parent: DiskTree.root, kind: .directory)
        fresh.accumulate(into: fonts, size: 40, privateSize: 40, items: 1)

        tree.graft(fresh, at: library)
        #expect(tree.node(atDisplayPath: "/Library/Caches") == nil)
        #expect(tree.size(tree.node(atDisplayPath: "/Library/Fonts")!) == 40)
        #expect(tree.size(library) == 40)
        #expect(tree.size(DiskTree.root) == 790)
    }

    @Test func detachedNodesStayDetachedThroughArchives() throws {
        var tree = sampleTree()
        tree.detach(tree.node(atDisplayPath: "/Library/Caches")!)
        let decoded = try ScanArchive.decode(ScanArchive(tree: tree, progress: ScanProgress(), scannedAt: .now).encoded()).tree
        #expect(decoded.node(atDisplayPath: "/Library/Caches") == nil)
    }

    @Test func exportsChildrenAsCSV() {
        let csv = sampleTree().csv(childrenOf: DiskTree.root)
        let lines = csv.split(separator: "\n")
        #expect(lines.first == "Path,Bytes,Items,Kind")
        #expect(lines[1] == "\"/Users\",700,1,folder")
        #expect(lines.last == "\"//(files)\",50,,files")
    }

    @Test func dominatedLevelsDontUseUpDepth() {
        var tree = DiskTree(rootPath: "/data", displayRootPath: "/")
        let users = tree.addNode(name: "Users", parent: DiskTree.root, kind: .directory)
        let me = tree.addNode(name: "me", parent: users, kind: .directory)
        let shared = tree.addNode(name: "Shared", parent: users, kind: .directory)
        tree.accumulate(into: shared, size: 1, privateSize: 0, items: 1)
        let movies = tree.addNode(name: "Movies", parent: me, kind: .directory)
        let code = tree.addNode(name: "Code", parent: me, kind: .directory)
        let clip = tree.addNode(name: "Clip", parent: movies, kind: .directory)
        tree.accumulate(into: clip, size: 500, privateSize: 0, items: 1)
        tree.accumulate(into: movies, size: 100, privateSize: 0, items: 1)
        tree.accumulate(into: code, size: 400, privateSize: 0, items: 1)
        let library = tree.addNode(name: "Library", parent: DiskTree.root, kind: .directory)
        tree.accumulate(into: library, size: 300, privateSize: 0, items: 1)

        let tiles = TreemapLayout.tiles(
            for: tree, focus: DiskTree.root, in: CGRect(x: 0, y: 0, width: 1200, height: 900),
            configuration: TreemapConfiguration(maxDepth: 2)
        )
        // Users → me is dominated, so me's children (Movies, Code) are still drawn with a depth of 2.
        #expect(tiles.contains { $0.title == "Movies" })
        #expect(tiles.contains { $0.title == "Code" })
    }

    @Test func tinyTilesMergeIntoOther() {
        var tree = DiskTree(rootPath: "/data", displayRootPath: "/")
        let big = tree.addNode(name: "Big", parent: DiskTree.root, kind: .directory)
        tree.accumulate(into: big, size: 10_000, privateSize: 0, items: 1)
        for index in 0..<30 {
            let small = tree.addNode(name: "s\(index)", parent: DiskTree.root, kind: .directory)
            tree.accumulate(into: small, size: 10, privateSize: 0, items: 1)
        }
        let tiles = TreemapLayout.tiles(
            for: tree, focus: DiskTree.root, in: CGRect(x: 0, y: 0, width: 400, height: 300),
            configuration: TreemapConfiguration(maxDepth: 1)
        )
        let other = tiles.first { if case .others = $0.content { true } else { false } }
        #expect(other?.title == "Other")
        if case .others(_, let count)? = other?.content { #expect(count == 30) }
        #expect(tiles.count == 2)
    }
}
