// FerryPreflightTests.swift
// CharonKitTests

import Foundation
import Testing
@testable import CharonKit

struct StubInspector: ProcessInspecting {
    var usages: [ProcessUsage] = []
    func processes(using path: String) -> [ProcessUsage] { usages }
}

struct FerryPreflightTests {
    private let home = URL(fileURLWithPath: "/Users/tester")

    private func preflight(_ inspector: StubInspector = StubInspector()) -> FerryPreflight {
        FerryPreflight(homeDirectory: home, resolver: MockResolver(), inspector: inspector)
    }

    private func shore(available: Int64 = 1_000_000_000_000, fileSystem: String = "apfs") -> VolumeInfo {
        VolumeInfo(
            id: "S", name: "Styx", mountPoint: URL(fileURLWithPath: "/Volumes/Styx"), uuid: "S",
            totalBytes: 2_000_000_000_000, availableBytes: available, fileSystem: fileSystem,
            isBoot: false, isInternal: false, isEjectable: true, isReadOnly: false
        )
    }

    private func severities(_ path: String) -> [PreflightIssue.Severity] {
        preflight().pathRules(path).map(\.0)
    }

    @Test func blocksSystemAndProtectedLocations() {
        for path in ["/System/Library", "/usr/bin", "/private/var", "/Library", "/Applications", "/Users/tester",
                     "/Users/tester/Library", "/Users/tester/Library/Containers/com.x", "/Users/tester/Library/Mobile Documents/y",
                     "/Applications/Xcode.app", "/Applications/Xcode.app/Contents", "/Users/tester/Documents"] {
            #expect(severities(path).contains(.blocker), "\(path) should be blocked")
        }
    }

    @Test func allowsOrdinaryDirectories() {
        #expect(severities("/Users/tester/Movies/Footage").isEmpty)
        #expect(severities("/Users/tester/Documents/Archive").isEmpty)
        #expect(severities("/usr/local/lib").allSatisfy { $0 == .warning })
        #expect(severities("/Users/tester/Library/Developer/Xcode/DerivedData") == [.warning])
    }

    @Test func userFacingPathStripsTheDataVolume() {
        #expect(FerryPreflight.userFacingPath("/System/Volumes/Data/Users/x") == "/Users/x")
        #expect(FerryPreflight.userFacingPath("/Users/x") == "/Users/x")
    }

    @Test func shoreRules() {
        let rules = preflight()
        #expect(rules.shoreRules(shore: nil, sourcePath: "/x", bytes: 1).map(\.severity) == [.blocker])
        #expect(rules.shoreRules(shore: shore(available: 500), sourcePath: "/x", bytes: 1_000).map(\.severity) == [.blocker])
        #expect(rules.shoreRules(shore: shore(fileSystem: "exfat"), sourcePath: "/x", bytes: 1).map(\.severity) == [.warning])
        #expect(rules.shoreRules(shore: shore(), sourcePath: "/x", bytes: 1).isEmpty)
    }

    @Test func runningAppsBlockAndOpenFilesWarn() async throws {
        let temp = try TempDirectory()
        let dir = try temp.directory("Stuff")
        let running = preflight(StubInspector(usages: [ProcessUsage(pid: 1, name: "Tool", reason: .runningFromHere)]))
        // Temp dirs live under /private/var, so filter to the process rule.
        let report = await running.check(source: dir, shore: shore())
        #expect(report.blockers.contains { $0.message.contains("Tool") })

        let open = preflight(StubInspector(usages: [ProcessUsage(pid: 1, name: "Editor", reason: .openFile)]))
        let openReport = await open.check(source: dir, shore: shore())
        #expect(!openReport.blockers.contains { $0.message.contains("Editor") })
        #expect(openReport.warnings.map(\.message).contains { $0.contains("Editor") })
    }

    @Test func refusesNestedAndRepeatFerries() async throws {
        let temp = try TempDirectory()
        let dir = try temp.directory("Outer/Inner")
        let record = FerryRecord(
            id: UUID(), originalPath: dir.path, shore: Shore(volumeUUID: "S", name: "Styx", mountPoint: URL(fileURLWithPath: "/Volumes/Styx")),
            shoreRelativePath: "Charon/x/Inner", bytes: 1, fileCount: 1, phase: .ferried, startedAt: Date()
        )
        let report = await preflight().check(source: dir.deletingLastPathComponent(), shore: shore(), existing: [record])
        #expect(!report.canFerry)
    }
}
