// FerrymanTests.swift
// CharonKitTests

import Foundation
import Synchronization
import Testing
@testable import CharonKit

/// Shore mounts the tests can plug and unplug.
final class MockResolver: VolumeResolving {
    private let mounts = Mutex<[String: URL]>([:])

    func plug(_ uuid: String, at url: URL) { mounts.withLock { $0[uuid] = url } }
    func unplug(_ uuid: String) { mounts.withLock { $0[uuid] = nil } }

    func mountPoint(forVolumeUUID uuid: String) -> URL? { mounts.withLock { $0[uuid] } }
    func volume(containing url: URL) -> VolumeInfo? { nil }
}

/// A home disk, a shore, a manifest and a directory to ferry.
final class FerryFixture {
    let home: TempDirectory
    let shoreDisk: TempDirectory
    let resolver = MockResolver()
    let store: ManifestStore
    let shore: Shore
    let source: URL

    init() throws {
        home = try TempDirectory()
        shoreDisk = try TempDirectory()
        store = ManifestStore(url: home.url.appendingPathComponent("support/manifest.plist"))
        shore = Shore(volumeUUID: "SHORE-UUID", name: "Styx", mountPoint: shoreDisk.url)
        resolver.plug(shore.volumeUUID, at: shoreDisk.url)

        try home.file("work/Project/a.bin", bytes: 300_000, seed: 1)
        try home.file("work/Project/nested/b.txt", bytes: 5_000, seed: 2)
        try home.file("work/Project/.hidden", bytes: 10, seed: 3)
        try FileManager.default.createSymbolicLink(
            atPath: home.url.appendingPathComponent("work/Project/link").path, withDestinationPath: "nested/b.txt"
        )
        source = home.url.appendingPathComponent("work/Project")
    }

    func ferryman(faults: FaultInjector? = nil) -> Ferryman {
        Ferryman(store: store, resolver: resolver, faults: faults)
    }

    func crash(at point: FaultPoint) -> FaultInjector {
        FaultInjector { if $0 == point { throw FaultInjector.Crash() } }
    }

    var sourceIsIntactDirectory: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: source.path)) == nil
            && FileManager.default.contents(atPath: source.appendingPathComponent("a.bin").path)?.count == 300_000
            && FileManager.default.contents(atPath: source.appendingPathComponent("nested/b.txt").path)?.count == 5_000
    }

    var isSymlink: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: source.path)) != nil
    }

    var shoreContents: [String] {
        let charon = shoreDisk.url.appendingPathComponent("Charon")
        return ((try? FileManager.default.contentsOfDirectory(atPath: charon.path)) ?? []).filter { $0 != "manifest.plist" }
    }

    var siblings: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: source.deletingLastPathComponent().path))?.sorted() ?? []
    }
}

struct FerrymanTests {

    @Test func ferryReplacesDirectoryWithWorkingSymlink() async throws {
        let fixture = try FerryFixture()
        let ferryman = fixture.ferryman()
        let record = try await ferryman.ferry(fixture.source, to: fixture.shore)

        #expect(record.phase == .ferried)
        #expect(record.treeDigest != nil)
        #expect(fixture.isSymlink)
        #expect(fixture.siblings == ["Project"])
        // Reads through the symlink land on the shore.
        let data = try Data(contentsOf: fixture.source.appendingPathComponent("nested/b.txt"))
        #expect(data.count == 5_000)
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: fixture.source.appendingPathComponent("link").path)
        #expect(link == "nested/b.txt")
        #expect(await ferryman.status(of: record) == .ferried)
        #expect(await ferryman.obols >= 300_000)
        #expect(try fixture.store.load().records.map(\.id) == [record.id])
    }

    @Test func bringHomeRestoresTheRealDirectory() async throws {
        let fixture = try FerryFixture()
        let ferryman = fixture.ferryman()
        let record = try await ferryman.ferry(fixture.source, to: fixture.shore)
        try await ferryman.bringHome(record.id)

        #expect(fixture.sourceIsIntactDirectory)
        #expect(fixture.shoreContents.isEmpty)
        #expect(fixture.siblings == ["Project"])
        #expect(await ferryman.records.isEmpty)
    }

    @Test func strandedWhenShoreUnpluggedAndRelocatedWhenRemountedElsewhere() async throws {
        let fixture = try FerryFixture()
        let ferryman = fixture.ferryman()
        let record = try await ferryman.ferry(fixture.source, to: fixture.shore)

        fixture.resolver.unplug(fixture.shore.volumeUUID)
        #expect(await ferryman.status(of: record) == .stranded)

        // Same drive, new mount point: move the data to simulate "Styx 1".
        let remount = try TempDirectory()
        try FileManager.default.removeItem(at: remount.url)
        try FileManager.default.moveItem(at: fixture.shoreDisk.url, to: remount.url)
        fixture.resolver.plug(fixture.shore.volumeUUID, at: remount.url)
        #expect(await ferryman.status(of: record) == .relocated(remount.url))

        try await ferryman.relink(record.id)
        #expect(await ferryman.status(of: record) == .ferried)
        #expect(FileManager.default.contents(atPath: fixture.source.appendingPathComponent("a.bin").path)?.count == 300_000)
        try FileManager.default.moveItem(at: remount.url, to: fixture.shoreDisk.url)
    }

    @Test func corruptedCopyFailsVerificationAndKeepsSource() async throws {
        let fixture = try FerryFixture()
        let shoreURL = fixture.shoreDisk.url
        let ferryman = fixture.ferryman(faults: FaultInjector { point in
            guard point == .beforeVerify else { return }
            let charon = shoreURL.appendingPathComponent("Charon")
            let id = try FileManager.default.contentsOfDirectory(atPath: charon.path).first { $0 != "manifest.plist" }!
            try Data(repeating: 0, count: 300_000).write(to: charon.appendingPathComponent("\(id)/Project/a.bin"))
        })

        await #expect(throws: FerryError.self) { try await ferryman.ferry(fixture.source, to: fixture.shore) }
        #expect(fixture.sourceIsIntactDirectory)
        #expect(fixture.shoreContents.isEmpty)
        #expect(await ferryman.records.isEmpty)
    }

    @Test func writesAfterVerificationAbortTheSwap() async throws {
        let fixture = try FerryFixture()
        let parent = fixture.source.deletingLastPathComponent()
        let ferryman = fixture.ferryman(faults: FaultInjector { point in
            guard point == .afterRenameSource else { return }
            let hidden = try FileManager.default.contentsOfDirectory(atPath: parent.path).first { $0.hasPrefix(".Project.charon-") }!
            try Data("late write".utf8).write(to: parent.appendingPathComponent("\(hidden)/new.txt"))
        })

        await #expect(throws: FerryError.self) { try await ferryman.ferry(fixture.source, to: fixture.shore) }
        #expect(fixture.sourceIsIntactDirectory)
        #expect(FileManager.default.fileExists(atPath: fixture.source.appendingPathComponent("new.txt").path))
        #expect(fixture.siblings == ["Project"])
        #expect(fixture.shoreContents.isEmpty)
    }

    @Test func cancellingLeavesSourceUntouched() async throws {
        let fixture = try FerryFixture()
        for index in 0..<40 { try fixture.home.file("work/Project/bulk/\(index).bin", bytes: 200_000) }
        let ferryman = fixture.ferryman()
        let (source, shore) = (fixture.source, fixture.shore)
        let task = Task { try await ferryman.ferry(source, to: shore) }
        try await Task.sleep(for: .milliseconds(5))
        task.cancel()
        _ = await task.result

        #expect(fixture.sourceIsIntactDirectory)
        if await ferryman.records.isEmpty {
            #expect(fixture.shoreContents.isEmpty)
        }
    }
}
