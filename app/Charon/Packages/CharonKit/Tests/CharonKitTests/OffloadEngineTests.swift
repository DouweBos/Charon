// OffloadEngineTests.swift
// CharonKitTests

import Foundation
import Synchronization
import Testing
@testable import CharonKit

/// Drive mounts the tests can plug and unplug.
final class MockResolver: VolumeResolving {
    private let mounts = Mutex<[String: URL]>([:])

    func plug(_ uuid: String, at url: URL) { mounts.withLock { $0[uuid] = url } }
    func unplug(_ uuid: String) { mounts.withLock { $0[uuid] = nil } }

    func mountPoint(forVolumeUUID uuid: String) -> URL? { mounts.withLock { $0[uuid] } }
    func volume(containing url: URL) -> VolumeInfo? { nil }
}

/// A home disk, a drive, a manifest and a directory to offload.
final class OffloadFixture {
    let home: TempDirectory
    let driveDisk: TempDirectory
    let resolver = MockResolver()
    let store: ManifestStore
    let drive: OffloadDrive
    let source: URL

    init() throws {
        home = try TempDirectory()
        driveDisk = try TempDirectory()
        store = ManifestStore(url: home.url.appendingPathComponent("support/manifest.plist"))
        drive = OffloadDrive(volumeUUID: "DRIVE-UUID", name: "Backup", mountPoint: driveDisk.url)
        resolver.plug(drive.volumeUUID, at: driveDisk.url)

        try home.file("work/Project/a.bin", bytes: 300_000, seed: 1)
        try home.file("work/Project/nested/b.txt", bytes: 5_000, seed: 2)
        try home.file("work/Project/.hidden", bytes: 10, seed: 3)
        try FileManager.default.createSymbolicLink(
            atPath: home.url.appendingPathComponent("work/Project/link").path, withDestinationPath: "nested/b.txt"
        )
        source = home.url.appendingPathComponent("work/Project")
    }

    func offloadEngine(faults: FaultInjector? = nil) -> OffloadEngine {
        OffloadEngine(store: store, resolver: resolver, faults: faults)
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

    var driveContents: [String] {
        let charon = driveDisk.url.appendingPathComponent("Charon")
        return ((try? FileManager.default.contentsOfDirectory(atPath: charon.path)) ?? []).filter { $0 != "manifest.plist" }
    }

    var siblings: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: source.deletingLastPathComponent().path))?.sorted() ?? []
    }
}

struct OffloadEngineTests {

    @Test func offloadReplacesDirectoryWithWorkingSymlink() async throws {
        let fixture = try OffloadFixture()
        let offloadEngine = fixture.offloadEngine()
        let record = try await offloadEngine.offload(fixture.source, to: fixture.drive)

        #expect(record.phase == .offloaded)
        #expect(record.treeDigest != nil)
        #expect(fixture.isSymlink)
        #expect(fixture.siblings == ["Project"])
        // Reads through the symlink land on the drive.
        let data = try Data(contentsOf: fixture.source.appendingPathComponent("nested/b.txt"))
        #expect(data.count == 5_000)
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: fixture.source.appendingPathComponent("link").path)
        #expect(link == "nested/b.txt")
        #expect(await offloadEngine.status(of: record) == .offloaded)
        #expect(await offloadEngine.freedBytes >= 300_000)
        #expect(try fixture.store.load().records.map(\.id) == [record.id])
    }

    @Test func moveBackRestoresTheRealDirectory() async throws {
        let fixture = try OffloadFixture()
        let offloadEngine = fixture.offloadEngine()
        let record = try await offloadEngine.offload(fixture.source, to: fixture.drive)
        try await offloadEngine.moveBack(record.id)

        #expect(fixture.sourceIsIntactDirectory)
        #expect(fixture.driveContents.isEmpty)
        #expect(fixture.siblings == ["Project"])
        #expect(await offloadEngine.records.isEmpty)
    }

    @Test func disconnectedWhenUnpluggedAndRemountedWhenMountedElsewhere() async throws {
        let fixture = try OffloadFixture()
        let offloadEngine = fixture.offloadEngine()
        let record = try await offloadEngine.offload(fixture.source, to: fixture.drive)

        fixture.resolver.unplug(fixture.drive.volumeUUID)
        #expect(await offloadEngine.status(of: record) == .disconnected)

        // Same drive, new mount point: move the data to simulate "Backup 1".
        let remount = try TempDirectory()
        try FileManager.default.removeItem(at: remount.url)
        try FileManager.default.moveItem(at: fixture.driveDisk.url, to: remount.url)
        fixture.resolver.plug(fixture.drive.volumeUUID, at: remount.url)
        #expect(await offloadEngine.status(of: record) == .remounted(remount.url))

        try await offloadEngine.relink(record.id)
        #expect(await offloadEngine.status(of: record) == .offloaded)
        #expect(FileManager.default.contents(atPath: fixture.source.appendingPathComponent("a.bin").path)?.count == 300_000)
        try FileManager.default.moveItem(at: remount.url, to: fixture.driveDisk.url)
    }

    @Test func corruptedCopyFailsVerificationAndKeepsSource() async throws {
        let fixture = try OffloadFixture()
        let driveURL = fixture.driveDisk.url
        let offloadEngine = fixture.offloadEngine(faults: FaultInjector { point in
            guard point == .beforeVerify else { return }
            let charon = driveURL.appendingPathComponent("Charon")
            let id = try FileManager.default.contentsOfDirectory(atPath: charon.path).first { $0 != "manifest.plist" }!
            try Data(repeating: 0, count: 300_000).write(to: charon.appendingPathComponent("\(id)/Project/a.bin"))
        })

        await #expect(throws: OffloadError.self) { try await offloadEngine.offload(fixture.source, to: fixture.drive) }
        #expect(fixture.sourceIsIntactDirectory)
        #expect(fixture.driveContents.isEmpty)
        #expect(await offloadEngine.records.isEmpty)
    }

    @Test func writesAfterVerificationAbortTheSwap() async throws {
        let fixture = try OffloadFixture()
        let parent = fixture.source.deletingLastPathComponent()
        let offloadEngine = fixture.offloadEngine(faults: FaultInjector { point in
            guard point == .afterRenameSource else { return }
            let hidden = try FileManager.default.contentsOfDirectory(atPath: parent.path).first { $0.hasPrefix(".Project.charon-") }!
            try Data("late write".utf8).write(to: parent.appendingPathComponent("\(hidden)/new.txt"))
        })

        await #expect(throws: OffloadError.self) { try await offloadEngine.offload(fixture.source, to: fixture.drive) }
        #expect(fixture.sourceIsIntactDirectory)
        #expect(FileManager.default.fileExists(atPath: fixture.source.appendingPathComponent("new.txt").path))
        #expect(fixture.siblings == ["Project"])
        #expect(fixture.driveContents.isEmpty)
    }

    @Test func cancellingLeavesSourceUntouched() async throws {
        let fixture = try OffloadFixture()
        for index in 0..<40 { try fixture.home.file("work/Project/bulk/\(index).bin", bytes: 200_000) }
        let offloadEngine = fixture.offloadEngine()
        let (source, drive) = (fixture.source, fixture.drive)
        let task = Task { try await offloadEngine.offload(source, to: drive) }
        try await Task.sleep(for: .milliseconds(5))
        task.cancel()
        _ = await task.result

        #expect(fixture.sourceIsIntactDirectory)
        if await offloadEngine.records.isEmpty {
            #expect(fixture.driveContents.isEmpty)
        }
    }

    @Test func checkCopyReadsBackEveryFile() async throws {
        let fixture = try OffloadFixture()
        let engine = fixture.offloadEngine()
        let record = try await engine.offload(fixture.source, to: fixture.drive)
        #expect(try await engine.checkCopy(record.id) == .intact)

        try Data("edited".utf8).write(to: fixture.source.appendingPathComponent("nested/b.txt"))
        #expect(try await engine.checkCopy(record.id) == .changedSinceOffload)
    }

    @Test func writesDuringVerificationAbortTheOffload() async throws {
        let fixture = try OffloadFixture()
        let source = fixture.source
        let engine = fixture.offloadEngine(faults: FaultInjector { point in
            guard point == .beforeVerify else { return }
            try Data("late".utf8).write(to: source.appendingPathComponent("nested/b.txt"))
        })

        await #expect(throws: OffloadError.self) { try await engine.offload(fixture.source, to: fixture.drive) }
        #expect(!fixture.isSymlink)
        #expect(FileManager.default.contents(atPath: source.appendingPathComponent("nested/b.txt").path) == Data("late".utf8))
        #expect(fixture.driveContents.isEmpty)
        #expect(await engine.records.isEmpty)
    }

    @Test func unreadableManifestBlocksChangesAndIsKept() async throws {
        let fixture = try OffloadFixture()
        try FileManager.default.createDirectory(at: fixture.store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: fixture.store.url)
        let engine = fixture.offloadEngine()

        #expect(await engine.manifestProblem != nil)
        await #expect(throws: OffloadError.self) { try await engine.offload(fixture.source, to: fixture.drive) }
        #expect(fixture.sourceIsIntactDirectory)
        #expect(try Data(contentsOf: fixture.store.url) == Data("not a plist".utf8))
    }

    @Test func readOnlyFoldersAreCleanedUp() async throws {
        let fixture = try OffloadFixture()
        try fixture.home.file("work/Project/locked/mod.go", bytes: 100)
        let locked = fixture.source.appendingPathComponent("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)

        let engine = fixture.offloadEngine()
        let record = try await engine.offload(fixture.source, to: fixture.drive)
        #expect(record.phase == .offloaded)
        #expect(fixture.siblings == ["Project"])

        try await engine.moveBack(record.id)
        #expect(fixture.driveContents.isEmpty)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
    }
}
