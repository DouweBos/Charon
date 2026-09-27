// ScanArchiveTests.swift
// CharonKitTests

import Foundation
import Testing
@testable import CharonKit

struct ScanArchiveTests {
    @Test func roundTripsTreeAndProgress() throws {
        var tree = DiskTree(rootPath: "/System/Volumes/Data", displayRootPath: "/")
        let users = tree.addNode(name: "Users", parent: DiskTree.root, kind: .directory)
        let movie = tree.addNode(name: "movie.mov", parent: users, kind: .file, size: 900, privateSize: 800)
        tree.accumulate(into: users, size: 1_000, privateSize: 900, items: 2)
        var progress = ScanProgress()
        progress.filesScanned = 2
        progress.unreadablePaths = ["/private/var/db"]
        progress.isComplete = true
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let decoded = try ScanArchive.decode(ScanArchive(tree: tree, progress: progress, scannedAt: date).encoded())

        #expect(decoded.scannedAt == date)
        #expect(decoded.progress == progress)
        #expect(decoded.tree.nodeCount == tree.nodeCount)
        #expect(decoded.tree.displayPath(movie) == "/Users/movie.mov")
        #expect(decoded.tree.size(DiskTree.root) == 1_000)
        #expect(decoded.tree.privateSize(movie) == 800)
        #expect(decoded.tree.kind(movie) == .file)
        #expect(decoded.tree.children(users) == [movie])
    }

    @Test func rejectsGarbage() {
        #expect(throws: (any Error).self) { try ScanArchive.decode(Data("nope".utf8)) }
    }
}
