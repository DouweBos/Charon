// FerryRecoveryTests.swift
// CharonKitTests
//
// Crash at every journal step, relaunch (new Ferryman on the same manifest), reconcile, and check that the
// data is always in exactly one sane place.

import Foundation
import Testing
@testable import CharonKit

struct FerryRecoveryTests {

    @Test(arguments: [FaultPoint.copiedFile(1), .beforeVerify, .afterRenameSource])
    func crashBeforeSymlinkRollsBack(point: FaultPoint) async throws {
        let fixture = try FerryFixture()
        await #expect(throws: FaultInjector.Crash.self) {
            try await fixture.ferryman(faults: fixture.crash(at: point)).ferry(fixture.source, to: fixture.shore)
        }

        let relaunched = fixture.ferryman()
        let outcomes = await relaunched.reconcile()
        #expect(outcomes.values.allSatisfy { $0 == .rolledBack })
        #expect(fixture.sourceIsIntactDirectory)
        #expect(fixture.siblings == ["Project"])
        #expect(fixture.shoreContents.isEmpty)
        #expect(await relaunched.records.isEmpty)
    }

    @Test(arguments: [FaultPoint.afterSymlink, .beforeCleanup])
    func crashAfterSymlinkRollsForward(point: FaultPoint) async throws {
        let fixture = try FerryFixture()
        await #expect(throws: FaultInjector.Crash.self) {
            try await fixture.ferryman(faults: fixture.crash(at: point)).ferry(fixture.source, to: fixture.shore)
        }

        let relaunched = fixture.ferryman()
        await relaunched.reconcile()
        let record = try #require(await relaunched.records.first)
        #expect(record.phase == .ferried)
        #expect(fixture.isSymlink)
        #expect(fixture.siblings == ["Project"])
        #expect(await relaunched.status(of: record) == .ferried)
    }

    @Test func shoreUnpluggedMidCopyKeepsSourceAndCleansUpLater() async throws {
        let fixture = try FerryFixture()
        let resolver = fixture.resolver
        let uuid = fixture.shore.volumeUUID
        let ferryman = fixture.ferryman(faults: FaultInjector { point in
            if point == .copiedFile(1) {
                resolver.unplug(uuid)
                throw POSIXError(.ENXIO)
            }
        })

        await #expect(throws: POSIXError.self) { try await ferryman.ferry(fixture.source, to: fixture.shore) }
        #expect(fixture.sourceIsIntactDirectory)
        #expect(await ferryman.records.first?.phase == .copying)
        #expect(!fixture.shoreContents.isEmpty)

        resolver.plug(uuid, at: fixture.shoreDisk.url)
        let outcomes = await ferryman.reconcile()
        #expect(outcomes.values.allSatisfy { $0 == .rolledBack })
        #expect(fixture.shoreContents.isEmpty)
        #expect(await ferryman.records.isEmpty)
    }

    @Test(arguments: [FaultPoint.returnCopiedFile(1), .afterRemoveSymlink, .beforeReturnCleanup])
    func crashWhileBringingHomeNeverLosesData(point: FaultPoint) async throws {
        let fixture = try FerryFixture()
        let record = try await fixture.ferryman().ferry(fixture.source, to: fixture.shore)
        await #expect(throws: FaultInjector.Crash.self) {
            try await fixture.ferryman(faults: fixture.crash(at: point)).bringHome(record.id)
        }

        let relaunched = fixture.ferryman()
        await relaunched.reconcile()
        #expect(fixture.siblings == ["Project"])
        if let remaining = await relaunched.records.first {
            #expect(remaining.phase == .ferried)
            #expect(fixture.isSymlink)
            #expect(await relaunched.status(of: remaining) == .ferried)
        } else {
            #expect(fixture.sourceIsIntactDirectory)
            #expect(fixture.shoreContents.isEmpty)
        }
    }

    @Test func shoreUnpluggedDuringBringHomeKeepsFerriedState() async throws {
        let fixture = try FerryFixture()
        let ferryman = fixture.ferryman()
        let record = try await ferryman.ferry(fixture.source, to: fixture.shore)
        let resolver = fixture.resolver
        let failing = fixture.ferryman(faults: FaultInjector { point in
            if point == .returnCopiedFile(1) {
                resolver.unplug(record.shore.volumeUUID)
                throw POSIXError(.ENXIO)
            }
        })

        await #expect(throws: POSIXError.self) { try await failing.bringHome(record.id) }
        #expect(await failing.records.first?.phase == .ferried)
        #expect(fixture.isSymlink)
        #expect(fixture.siblings == ["Project"])
        #expect(await failing.status(of: record) == .stranded)
    }
}
