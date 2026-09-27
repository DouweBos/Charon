// DiskScannerTests.swift
// CharonKitTests

import Foundation
import Testing
@testable import CharonKit

struct DiskScannerTests {

    private func scan(_ url: URL, options: ScanOptions = ScanOptions(largeFileThreshold: 100_000)) async throws -> ScanUpdate {
        var last: ScanUpdate?
        for try await update in DiskScanner(options: options).scan(root: url, displayRootPath: "/") {
            last = update
        }
        return try #require(last)
    }

    @Test func sizesRollUpAndLargeFilesBecomeNodes() async throws {
        let temp = try TempDirectory()
        try temp.file("a/big.bin", bytes: 300_000)
        try temp.file("a/small.txt", bytes: 1_000)
        try temp.file("b/c/deep.bin", bytes: 200_000)
        try temp.directory("empty")

        let result = try await scan(temp.url)
        let tree = result.tree
        #expect(result.progress.isComplete)

        let folder = try #require(tree.node(atDisplayPath: "/a"))
        let big = try #require(tree.node(atDisplayPath: "/a/big.bin"))
        #expect(tree.kind(big) == .file)
        #expect(tree.node(atDisplayPath: "/a/small.txt") == nil)
        #expect(tree.size(folder) >= 301_000)
        #expect(tree.looseFilesSize(folder) >= 1_000)

        let childTotal = tree.children(DiskTree.root).reduce(Int64(0)) { $0 + tree.size($1) }
        #expect(tree.size(DiskTree.root) == childTotal + tree.looseFilesSize(DiskTree.root))
        #expect(tree.realPath(big) == temp.url.path + "/a/big.bin")
    }

    @Test func hardlinksAreCountedOnce() async throws {
        let temp = try TempDirectory()
        let original = try temp.file("x/data.bin", bytes: 400_000)
        try temp.directory("y")
        try FileManager.default.linkItem(at: original, to: temp.url.appendingPathComponent("y/data.bin"))

        let tree = try await scan(temp.url).tree
        #expect(tree.size(DiskTree.root) >= 400_000)
        #expect(tree.size(DiskTree.root) < 800_000)
    }

    @Test func symlinksAreNotFollowed() async throws {
        let temp = try TempDirectory()
        let outside = try TempDirectory()
        try outside.file("huge.bin", bytes: 500_000)
        try FileManager.default.createSymbolicLink(at: temp.url.appendingPathComponent("link"), withDestinationURL: outside.url)

        let tree = try await scan(temp.url).tree
        #expect(tree.size(DiskTree.root) < 100_000)
    }

    @Test func collapsesSingleChildChains() async throws {
        let temp = try TempDirectory()
        try temp.file("opt/homebrew/Cellar/pkg.bin", bytes: 200_000)
        try temp.file("other.bin", bytes: 200_000)

        let tree = try await scan(temp.url).tree
        let opt = try #require(tree.node(atDisplayPath: "/opt"))
        #expect(tree.collapsedName(tree.collapsedChain(from: opt)) == "opt/homebrew/Cellar")
    }

    @Test func unreadableDirectoriesAreCounted() async throws {
        let temp = try TempDirectory()
        let locked = try temp.directory("locked")
        try temp.file("locked/secret.bin", bytes: 10)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let result = try await scan(temp.url)
        #expect(result.progress.unreadableDirectories == 1)
    }

    @Test func skipsExcludedDirectories() async throws {
        let temp = try TempDirectory()
        try temp.file("keep/a.bin", bytes: 200_000)
        try temp.file("skip/b.bin", bytes: 200_000)
        var options = ScanOptions(largeFileThreshold: 100_000)
        options.excludedPaths = [temp.url.path + "/skip"]

        let tree = try await scan(temp.url, options: options).tree
        #expect(tree.node(atDisplayPath: "/keep") != nil)
        #expect(tree.node(atDisplayPath: "/skip") == nil)
    }
}
