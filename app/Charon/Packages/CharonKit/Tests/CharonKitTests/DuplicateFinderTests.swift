// DuplicateFinderTests.swift
// CharonKitTests

import Foundation
import Testing
@testable import CharonKit

struct DuplicateFinderTests {
    @Test func findsIdenticalFilesButNotSameSizedOnes() async throws {
        let temp = try TempDirectory()
        try temp.file("a/one.bin", bytes: 300_000, seed: 1)
        try temp.file("b/copy.bin", bytes: 300_000, seed: 1)
        try temp.file("c/other.bin", bytes: 300_000, seed: 9)
        var tree: DiskTree?
        for try await update in DiskScanner(options: ScanOptions(largeFileThreshold: 100_000)).scan(root: temp.url) {
            tree = update.tree
        }
        let groups = try DuplicateFinder(minimumBytes: 100_000).find(in: try #require(tree))
        #expect(groups.count == 1)
        #expect(groups[0].paths.map { ($0 as NSString).lastPathComponent }.sorted() == ["copy.bin", "one.bin"])
        #expect(groups[0].reclaimable == 300_000)
    }
}
