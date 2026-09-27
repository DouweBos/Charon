// AdminScanTests.swift
// CharonKitTests

import Foundation
import Testing
@testable import CharonKit

struct AdminScanTests {
    @Test func argumentsRoundTrip() throws {
        let request = AdminScanRequest(
            root: "/System/Volumes/Data", displayRoot: "/", outputDirectory: "/Users/me/Library/Caches/x",
            ownerUID: 501, largeFileThreshold: 50_000_000, excludedPaths: ["/Users/me/VMs", "/opt/x"]
        )
        #expect(AdminScanRequest(arguments: request.arguments) == request)
    }

    @Test func rejectsMalformedArguments() {
        #expect(AdminScanRequest(arguments: ["--root", "relative", "--display", "/", "--output", "/o", "--owner", "1", "--threshold", "1"]) == nil)
        #expect(AdminScanRequest(arguments: ["--root", "/"]) == nil)
        #expect(AdminScanRequest(arguments: ["--root", "/", "--display", "/", "--output", "/a/../etc", "--owner", "1", "--threshold", "1"]) == nil)
    }

    @Test func refusesSymlinkedOutputDirectory() throws {
        let temp = try TempDirectory()
        let real = try temp.directory("real")
        let link = temp.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(throws: (any Error).self) {
            try AdminScanOutput.write(Data("x".utf8), name: "result", in: link.path, owner: getuid())
        }
        try AdminScanOutput.write(Data("x".utf8), name: "result", in: real.path, owner: getuid())
        #expect(FileManager.default.contents(atPath: real.path + "/result") == Data("x".utf8))
    }
}
