// OffloadSuggesterTests.swift
// CharonKitTests

import Foundation
import Testing
@testable import CharonKit

struct OffloadSuggesterTests {
    @Test func picksLargestSafeFoldersWithoutOverlap() {
        var tree = DiskTree(rootPath: "/data", displayRootPath: "/")
        let users = tree.addNode(name: "Users", parent: DiskTree.root, kind: .directory)
        let me = tree.addNode(name: "me", parent: users, kind: .directory)
        let movies = tree.addNode(name: "Movies", parent: me, kind: .directory)
        let footage = tree.addNode(name: "Footage", parent: movies, kind: .directory)
        let library = tree.addNode(name: "Library", parent: me, kind: .directory)
        let documents = tree.addNode(name: "Documents", parent: me, kind: .directory)
        let archive = tree.addNode(name: "Archive", parent: documents, kind: .directory)
        tree.accumulate(into: footage, size: 50, privateSize: 0, items: 1)
        tree.accumulate(into: movies, size: 5, privateSize: 0, items: 1)
        tree.accumulate(into: library, size: 80, privateSize: 0, items: 1)
        tree.accumulate(into: archive, size: 30, privateSize: 0, items: 1)

        let suggester = OffloadSuggester(
            preflight: OffloadPreflight(homeDirectory: URL(fileURLWithPath: "/Users/me"), resolver: MockResolver(), inspector: StubInspector()),
            minimumBytes: 10
        )
        let paths = suggester.suggestions(in: tree).map(\.path)
        // Library is blocked outright, Documents must stay, Movies wins over its child Footage.
        #expect(paths == ["/Users/me/Movies", "/Users/me/Documents/Archive"])
    }
}
