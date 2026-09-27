// CleanupTests.swift
// CharonKitTests

import Foundation
import Testing
@testable import CharonKit

struct TrashPolicyTests {
    private let policy = TrashPolicy(
        homeDirectory: URL(fileURLWithPath: "/Users/tester"), ferriedPaths: ["/Users/tester/Movies/Footage"]
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
