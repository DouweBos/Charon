// OffloadRecoveryTests.swift
// CharonKitTests
//
// Crash at every journal step, relaunch (new OffloadEngine on the same manifest), reconcile, and check that the
// data is always in exactly one sane place.

import Foundation
import Testing
@testable import CharonKit

struct OffloadRecoveryTests {

    @Test(arguments: [FaultPoint.copiedFile(1), .beforeVerify, .afterRenameSource])
    func crashBeforeSymlinkRollsBack(point: FaultPoint) async throws {
        let fixture = try OffloadFixture()
        await #expect(throws: FaultInjector.Crash.self) {
            try await fixture.offloadEngine(faults: fixture.crash(at: point)).offload(fixture.source, to: fixture.drive)
        }

        let relaunched = fixture.offloadEngine()
        let outcomes = await relaunched.reconcile()
        #expect(outcomes.values.allSatisfy { $0 == .rolledBack })
        #expect(fixture.sourceIsIntactDirectory)
        #expect(fixture.siblings == ["Project"])
        #expect(fixture.driveContents.isEmpty)
        #expect(await relaunched.records.isEmpty)
    }

    @Test(arguments: [FaultPoint.afterSymlink, .beforeCleanup])
    func crashAfterSymlinkRollsForward(point: FaultPoint) async throws {
        let fixture = try OffloadFixture()
        await #expect(throws: FaultInjector.Crash.self) {
            try await fixture.offloadEngine(faults: fixture.crash(at: point)).offload(fixture.source, to: fixture.drive)
        }

        let relaunched = fixture.offloadEngine()
        await relaunched.reconcile()
        let record = try #require(await relaunched.records.first)
        #expect(record.phase == .offloaded)
        #expect(fixture.isSymlink)
        #expect(fixture.siblings == ["Project"])
        #expect(await relaunched.status(of: record) == .offloaded)
    }

    @Test func driveUnpluggedMidCopyKeepsSourceAndCleansUpLater() async throws {
        let fixture = try OffloadFixture()
        let resolver = fixture.resolver
        let uuid = fixture.drive.volumeUUID
        let offloadEngine = fixture.offloadEngine(faults: FaultInjector { point in
            if point == .copiedFile(1) {
                resolver.unplug(uuid)
                throw POSIXError(.ENXIO)
            }
        })

        await #expect(throws: POSIXError.self) { try await offloadEngine.offload(fixture.source, to: fixture.drive) }
        #expect(fixture.sourceIsIntactDirectory)
        #expect(await offloadEngine.records.first?.phase == .copying)
        #expect(!fixture.driveContents.isEmpty)

        resolver.plug(uuid, at: fixture.driveDisk.url)
        let outcomes = await offloadEngine.reconcile()
        #expect(outcomes.values.allSatisfy { $0 == .rolledBack })
        #expect(fixture.driveContents.isEmpty)
        #expect(await offloadEngine.records.isEmpty)
    }

    @Test(arguments: [FaultPoint.returnCopiedFile(1), .afterRemoveSymlink, .beforeReturnCleanup])
    func crashWhileMovingBackNeverLosesData(point: FaultPoint) async throws {
        let fixture = try OffloadFixture()
        let record = try await fixture.offloadEngine().offload(fixture.source, to: fixture.drive)
        await #expect(throws: FaultInjector.Crash.self) {
            try await fixture.offloadEngine(faults: fixture.crash(at: point)).moveBack(record.id)
        }

        let relaunched = fixture.offloadEngine()
        await relaunched.reconcile()
        #expect(fixture.siblings == ["Project"])
        if let remaining = await relaunched.records.first {
            #expect(remaining.phase == .offloaded)
            #expect(fixture.isSymlink)
            #expect(await relaunched.status(of: remaining) == .offloaded)
        } else {
            #expect(fixture.sourceIsIntactDirectory)
            #expect(fixture.driveContents.isEmpty)
        }
    }

    @Test func driveUnpluggedDuringMoveBackKeepsOffloadedState() async throws {
        let fixture = try OffloadFixture()
        let offloadEngine = fixture.offloadEngine()
        let record = try await offloadEngine.offload(fixture.source, to: fixture.drive)
        let resolver = fixture.resolver
        let failing = fixture.offloadEngine(faults: FaultInjector { point in
            if point == .returnCopiedFile(1) {
                resolver.unplug(record.drive.volumeUUID)
                throw POSIXError(.ENXIO)
            }
        })

        await #expect(throws: POSIXError.self) { try await failing.moveBack(record.id) }
        #expect(await failing.records.first?.phase == .offloaded)
        #expect(fixture.isSymlink)
        #expect(fixture.siblings == ["Project"])
        #expect(await failing.status(of: record) == .disconnected)
    }
}
