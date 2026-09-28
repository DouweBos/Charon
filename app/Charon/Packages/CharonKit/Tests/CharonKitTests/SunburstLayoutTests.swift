// SunburstLayoutTests.swift
// CharonKitTests

import Foundation
import Testing
@testable import CharonKit

struct SunburstLayoutTests {
    private func tree() -> DiskTree {
        var tree = DiskTree(rootPath: "/data", displayRootPath: "/")
        let users = tree.addNode(name: "Users", parent: DiskTree.root, kind: .directory)
        let me = tree.addNode(name: "me", parent: users, kind: .directory)
        tree.accumulate(into: me, size: 600, privateSize: 0, items: 1)
        let library = tree.addNode(name: "Library", parent: DiskTree.root, kind: .directory)
        tree.accumulate(into: library, size: 300, privateSize: 0, items: 1)
        let tiny = tree.addNode(name: "tiny", parent: DiskTree.root, kind: .directory)
        tree.accumulate(into: tiny, size: 1, privateSize: 0, items: 1)
        return tree
    }

    @Test func innerRingCoversTheCircleAndChildrenStayInsideParents() {
        let segments = SunburstLayout.segments(for: tree(), focus: DiskTree.root, minimumAngle: 0.05)
        let inner = segments.filter { $0.depth == 1 }
        #expect(abs(inner.map { $0.endAngle - $0.startAngle }.reduce(0, +) - 2 * .pi) < 1e-9)
        #expect(inner.contains { $0.title == "Smaller items" })

        let users = inner.first { $0.title == "Users/me" }!
        #expect(abs((users.endAngle - users.startAngle) - 2 * .pi * 600 / 901) < 1e-9)
    }

    @Test func hitTestFindsTheSegmentUnderAnAngle() {
        let segments = SunburstLayout.segments(for: tree(), focus: DiskTree.root)
        #expect(SunburstLayout.hitTest(segments, angle: 0.1, depth: 1)?.title == "Users/me")
        #expect(SunburstLayout.hitTest(segments, angle: 0.1, depth: 3) == nil)
    }

    @Test func dominantFolderLetsItsChildrenPickColors() {
        var tree = DiskTree(rootPath: "/data", displayRootPath: "/")
        let users = tree.addNode(name: "Users", parent: DiskTree.root, kind: .directory)
        let movies = tree.addNode(name: "Movies", parent: users, kind: .directory)
        let code = tree.addNode(name: "Code", parent: users, kind: .directory)
        tree.accumulate(into: movies, size: 500, privateSize: 0, items: 1)
        tree.accumulate(into: code, size: 400, privateSize: 0, items: 1)
        let other = tree.addNode(name: "Other", parent: DiskTree.root, kind: .directory)
        tree.accumulate(into: other, size: 10, privateSize: 0, items: 1)

        let segments = SunburstLayout.segments(for: tree, focus: DiskTree.root, minimumAngle: 0.001)
        let colors = Set(segments.filter { $0.depth == 2 }.map(\.colorIndex))
        #expect(colors.count == 2)
    }
}
