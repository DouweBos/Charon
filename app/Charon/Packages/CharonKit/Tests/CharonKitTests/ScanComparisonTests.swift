// ScanComparisonTests.swift
// CharonKitTests

import Foundation
import Testing
@testable import CharonKit

struct ScanComparisonTests {
    private func tree(derivedData: Int64, downloads: Int64, newFolder: Int64? = nil) -> DiskTree {
        var tree = DiskTree(rootPath: "/data", displayRootPath: "/")
        let users = tree.addNode(name: "Users", parent: DiskTree.root, kind: .directory)
        let me = tree.addNode(name: "me", parent: users, kind: .directory)
        let library = tree.addNode(name: "Library", parent: me, kind: .directory)
        let derived = tree.addNode(name: "DerivedData", parent: library, kind: .directory)
        let downloadsNode = tree.addNode(name: "Downloads", parent: me, kind: .directory)
        tree.accumulate(into: derived, size: derivedData, privateSize: 0, items: 1)
        tree.accumulate(into: downloadsNode, size: downloads, privateSize: 0, items: 1)
        if let newFolder {
            let fresh = tree.addNode(name: "New", parent: me, kind: .directory)
            tree.accumulate(into: fresh, size: newFolder, privateSize: 0, items: 1)
        }
        return tree
    }

    @Test func narrowsGrowthToTheFolderThatExplainsIt() {
        let comparison = ScanComparison(
            previous: tree(derivedData: 1_000, downloads: 500),
            current: tree(derivedData: 9_000, downloads: 600, newFolder: 3_000),
            previousDate: .distantPast
        )
        let items = comparison.topGrowth(minimum: 50)
        #expect(items.map(\.path) == ["/Users/me/Library/DerivedData", "/Users/me/New", "/Users/me/Downloads"])
        #expect(items[0].delta == 8_000)
        #expect(items[1].isNew)
        #expect(comparison.delta(atDisplayPath: "/Users/me/Downloads") == 100)
        #expect(comparison.delta(atDisplayPath: "/Users/me/New") == nil)
    }
}
