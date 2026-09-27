// CleanupTests.swift
// CharonKitTests

import Foundation
import Testing
@testable import CharonKit

struct TrashPolicyTests {
    private let policy = TrashPolicy(
        homeDirectory: URL(fileURLWithPath: "/Users/tester"), offloadedPaths: ["/Users/tester/Movies/Footage"]
    )

    @Test func refusesProtectedLocations() {
        for path in ["/System/Library/Fonts", "/Applications", "/Users/tester", "/Users/tester/Library",
                     "/Users/tester/Library/Keychains/login.keychain-db", "/Applications/Xcode.app/Contents/Developer",
                     "/Users/tester/Movies/Footage", "/Users/tester/Movies/Footage/clip.mov",
                     "/System/Volumes/Data/Users/tester"] {
            #expect(policy.refusal(for: path) != nil, "\(path) should be refused")
        }
    }

    @Test func allowsUserContent() {
        for path in ["/Users/tester/Downloads/big.dmg", "/Users/tester/Library/Caches/com.example",
                     "/Applications/Old.app", "/Users/tester/Movies/Other"] {
            #expect(policy.refusal(for: path) == nil, "\(path) should be allowed")
        }
    }
}

struct CollectorSetTests {
    @Test func keepsTheSetMinimal() {
        var set = CollectorSet()
        set.add(.init(path: "/a/b/c", bytes: 10, isDirectory: false))
        set.add(.init(path: "/a/x", bytes: 5, isDirectory: false))
        set.add(.init(path: "/a/b", bytes: 50, isDirectory: true))
        #expect(set.items.map(\.path) == ["/a/b", "/a/x"])

        set.add(.init(path: "/a/b/d", bytes: 1, isDirectory: false))
        #expect(set.items.count == 2)
        #expect(set.totalBytes == 55)
        #expect(set.contains("/a/b/anything"))

        set.remove("/a/b")
        #expect(set.items.map(\.path) == ["/a/x"])
    }
}

struct CleanResolverTests {
    @Test func wildcards() {
        #expect(CleanResolver.wildcard("Install macOS*.app", matches: "Install macOS Tahoe.app"))
        #expect(!CleanResolver.wildcard("Install macOS*.app", matches: "Xcode.app"))
        #expect(CleanResolver.wildcard("*DeviceSupport", matches: "iOS DeviceSupport"))
        #expect(!CleanResolver.wildcard("*DeviceSupport", matches: "DeviceSupport.old"))
    }

    @Test func expandsContentsAndSkipsExcludes() throws {
        let home = try TempDirectory()
        try home.file("Library/Caches/com.app/data", bytes: 10)
        try home.file("Library/Caches/Homebrew/pkg", bytes: 10)
        try home.file("Library/Developer/Xcode/iOS DeviceSupport/18.0/x", bytes: 10)
        try home.file("Library/Developer/Xcode/tvOS DeviceSupport/18.0/x", bytes: 10)
        let resolver = CleanResolver(homeDirectory: home.url)

        let caches = try #require(CleanCatalog.all.first { $0.id == "system.caches" })
        #expect(resolver.items(for: caches).map(\.lastPathComponent) == ["com.app"])

        let support = try #require(CleanCatalog.all.first { $0.id == "xcode.deviceSupport" })
        #expect(resolver.items(for: support).count == 2)
    }

    @Test func catalogIdsAreUnique() {
        #expect(Set(CleanCatalog.all.map(\.id)).count == CleanCatalog.all.count)
    }
}

struct CleanMeasurerTests {
    @Test func measuresChildrenAndSkipsExcludes() async throws {
        let home = try TempDirectory()
        try home.file("Library/Caches/com.big/blob", bytes: 400_000)
        try home.file("Library/Caches/small.db", bytes: 5_000)
        try home.file("Library/Caches/Homebrew/pkg", bytes: 300_000)
        let measurer = CleanMeasurer(resolver: CleanResolver(homeDirectory: home.url))
        let caches = try #require(CleanCatalog.all.first { $0.id == "system.caches" })

        let items = try await measurer.measure(caches)
        #expect(items.map(\.url.lastPathComponent) == ["com.big", "small.db"])
        #expect(items[0].bytes >= 400_000)
    }
}

struct AppInventoryTests {
    @Test func findsLeftoversByBundleIDAndName() throws {
        let home = try TempDirectory()
        try home.file("Library/Application Support/com.example.Tool/db", bytes: 10)
        try home.file("Library/Caches/Tool/cache", bytes: 10)
        try home.file("Library/Preferences/com.example.Tool.plist", bytes: 10)
        try home.file("Library/Group Containers/ABCDE12345.com.example.Tool/x", bytes: 10)
        try home.file("Library/LaunchAgents/com.example.Tool.helper.plist", bytes: 10)
        try home.file("Library/Caches/com.other.App/cache", bytes: 10)
        let inventory = AppInventory(homeDirectory: home.url, appFolders: [])

        let candidates = inventory.candidates(bundleID: "com.example.Tool", name: "Tool")
        #expect(candidates.map(\.kind).sorted() == ["Application Support", "Caches", "Group container", "Launch agent", "Preferences"])
        #expect(candidates.filter(\.byName).map(\.kind) == ["Caches"])
    }
}
