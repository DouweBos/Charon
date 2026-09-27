// Offload/OffloadEngine+MoveBack.swift
// CharonKit
//
// Copies an offloaded folder back to where it came from, verifies it, swaps out the link, then removes the
// drive copy. Mirrors the offload journal so recovery can finish or roll back.

import Darwin
import Foundation

extension OffloadEngine {

    public func moveBack(
        _ id: UUID, progress: @escaping @Sendable (OffloadProgress) -> Void = { _ in }
    ) async throws {
        let plan = try await prepareMoveBack(id)
        // Re-check after the awaits above: another call may have started on this record meanwhile.
        guard !inFlight.contains(id), record(id)?.phase == .offloaded else { throw OffloadError.recordBusy }
        var record = plan.record
        let (mount, copy, linkTarget, bytes) = (plan.mount, plan.copy, plan.linkTarget, plan.bytes)

        let staging = record.returnStagingURL
        inFlight.insert(id)
        defer { inFlight.remove(id) }
        let baseline = try await runBlocking { _ in try TreeFingerprint.capture(copy) }
        record.phase = .returnCopying
        try commit(record)
        do {
            try await copyTree(from: copy, to: staging, bytes: bytes, fault: FaultPoint.returnCopiedFile, progress: progress)

            record.phase = .returnVerifying
            try commit(record)
            _ = try await verifyTree(source: copy, copy: staging, bytes: bytes, progress: progress)

            record.phase = .returnSwapping
            try commit(record)
            progress(OffloadProgress(stage: .swapping, bytesDone: bytes, bytesTotal: bytes))
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: record.originalPath)) == linkTarget else {
                throw OffloadError.brokenLink("\(record.originalPath) changed while moving it back.")
            }
            guard (try? TreeFingerprint.capture(copy)) == baseline else {
                throw OffloadError.changedDuringOffload(record.originalPath)
            }
            try posixCheck(unlink(record.originalPath))
            try fault(.afterRemoveSymlink)
            try posixCheck(rename(staging.path, record.originalPath))

            try fault(.beforeReturnCleanup)
            record.phase = .returnCleaning
            try commit(record)
            progress(OffloadProgress(stage: .cleaning, bytesDone: bytes, bytesTotal: bytes))
            let container = record.containerURL(mountPoint: mount)
            // Writes through the link between the last check and the unlink would only exist on the drive; keep it.
            guard (try? TreeFingerprint.capture(copy)) == baseline else {
                try remove(record)
                throw OffloadError.keptDriveCopy(
                    "Moved back, but files on \(record.drive.name) changed during the move. Its copy was kept at \(copy.path)."
                )
            }
            try await runBlocking { _ in try Self.removeTree(container) }
            try remove(record)
        } catch is FaultInjector.Crash {
            throw FaultInjector.Crash()
        } catch OffloadError.keptDriveCopy(let message) {
            // Already resolved: the record is gone on purpose and recovery must not delete the kept copy.
            throw OffloadError.keptDriveCopy(message)
        } catch {
            record.lastError = error.localizedDescription
            try? commit(record)
            _ = await recover(id)
            throw error
        }
    }

    struct MoveBackPlan {
        var record: OffloadRecord
        var mount: URL
        var copy: URL
        var linkTarget: String
        var bytes: Int64
    }

    private func prepareMoveBack(_ id: UUID) async throws -> MoveBackPlan {
        guard let record = record(id) else { throw OffloadError.recordNotFound }
        guard record.phase == .offloaded else { throw OffloadError.recordBusy }
        guard let mount = resolver.mountPoint(forVolumeUUID: record.drive.volumeUUID) else {
            throw OffloadError.driveUnavailable(record.drive.name)
        }
        let copy = record.copyURL(mountPoint: mount)
        guard let linkTarget = try? FileManager.default.destinationOfSymbolicLink(atPath: record.originalPath) else {
            throw OffloadError.brokenLink("\(record.originalPath) is no longer a symlink, so it can't be replaced.")
        }
        guard FileManager.default.fileExists(atPath: copy.path) else {
            throw OffloadError.brokenLink("The copy on \(record.drive.name) is missing.")
        }
        let (bytes, _) = try await runBlocking { _ in try Self.measure(copy) }
        if let home = resolver.volume(containing: record.originalURL.deletingLastPathComponent()),
           home.availableBytes < bytes {
            throw OffloadError.notEnoughSpace(needed: bytes, available: home.availableBytes)
        }
        return MoveBackPlan(record: record, mount: mount, copy: copy, linkTarget: linkTarget, bytes: bytes)
    }
}
