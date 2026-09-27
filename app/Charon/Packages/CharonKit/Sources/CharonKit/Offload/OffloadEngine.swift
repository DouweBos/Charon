// Offload/OffloadEngine.swift
// CharonKit
//
// Offloads directories to a drive and moves them back. Every step is journaled in the manifest before it
// runs, so a crash, cancel or unplugged drive always leaves the original or a verified copy in place.

import Darwin
import Foundation

public struct OffloadProgress: Sendable, Hashable {
    public enum Stage: String, Sendable { case copying, verifying, swapping, cleaning }

    public var stage: Stage
    public var bytesDone: Int64
    public var bytesTotal: Int64

    public var fraction: Double {
        bytesTotal > 0 ? min(Double(bytesDone) / Double(bytesTotal), 1) : 0
    }
}

/// Points where tests inject failures. Throwing `FaultInjector.Crash` stops the operation as if the process
/// died there: no rollback runs, the journal stays as written.
public enum FaultPoint: Sendable, Hashable {
    case copiedFile(Int)
    case beforeVerify
    case afterRenameSource
    case afterSymlink
    case beforeCleanup
    case returnCopiedFile(Int)
    case afterRemoveSymlink
    case beforeReturnCleanup
}

public struct FaultInjector: Sendable {
    public struct Crash: Error {
        public init() {}
    }

    public var hook: @Sendable (FaultPoint) throws -> Void

    public init(hook: @escaping @Sendable (FaultPoint) throws -> Void) {
        self.hook = hook
    }
}

public actor OffloadEngine {
    private let store: ManifestStore
    private let resolver: any VolumeResolving
    private let faults: FaultInjector?
    private let driveFolder: String
    private var manifest: OffloadManifest

    public init(
        store: ManifestStore, resolver: any VolumeResolving = VolumeCatalog(),
        driveFolder: String = "Charon", faults: FaultInjector? = nil
    ) {
        self.store = store
        self.resolver = resolver
        self.driveFolder = driveFolder
        self.faults = faults
        manifest = (try? store.load()) ?? OffloadManifest()
    }

    public var records: [OffloadRecord] { manifest.records }

    /// Total bytes currently living on other drives.
    public var freedBytes: Int64 {
        manifest.records.filter { $0.phase == .offloaded }.reduce(0) { $0 + $1.bytes }
    }

    // MARK: - Offload

    public func offload(
        _ source: URL, to drive: OffloadDrive, progress: @escaping @Sendable (OffloadProgress) -> Void = { _ in }
    ) async throws -> OffloadRecord {
        let source = source.standardizedFileURL
        var info = stat()
        guard lstat(source.path, &info) == 0 else { throw OffloadError.sourceMissing(source.path) }
        guard info.st_mode & S_IFMT == S_IFDIR else { throw OffloadError.sourceNotADirectory(source.path) }
        guard let mount = resolver.mountPoint(forVolumeUUID: drive.volumeUUID) else {
            throw OffloadError.driveUnavailable(drive.name)
        }
        guard !manifest.records.contains(where: { $0.originalPath == source.path }) else { throw OffloadError.recordBusy }

        let (bytes, files) = try await runBlocking { _ in try Self.measure(source) }
        let id = UUID()
        var record = OffloadRecord(
            id: id, originalPath: source.path,
            drive: OffloadDrive(volumeUUID: drive.volumeUUID, name: drive.name, mountPoint: mount),
            driveRelativePath: "\(driveFolder)/\(id.uuidString)/\(source.lastPathComponent)",
            bytes: bytes, fileCount: files, phase: .copying, startedAt: Date()
        )
        try commit(record)

        do {
            let copy = record.copyURL(mountPoint: mount)
            try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            let faults = faults
            try await runBlocking { flag in
                var copier = TreeCopier(flag: flag) { progress(OffloadProgress(stage: .copying, bytesDone: $0, bytesTotal: bytes)) }
                copier.afterFile = { try faults?.hook(.copiedFile($0)) }
                try copier.copy(from: source, to: copy)
            }

            try fault(.beforeVerify)
            record.phase = .verifying
            try commit(record)
            let digest = try await runBlocking { flag in
                try TreeVerifier(flag: flag) { progress(OffloadProgress(stage: .verifying, bytesDone: $0, bytesTotal: bytes)) }
                    .verify(source: source, copy: copy)
            }
            let fingerprint = try TreeFingerprint.capture(source)
            record.treeDigest = digest

            progress(OffloadProgress(stage: .swapping, bytesDone: bytes, bytesTotal: bytes))
            record.phase = .swapping
            try commit(record)
            try swapInSymlink(record, copy: copy, fingerprint: fingerprint)

            try fault(.beforeCleanup)
            record.phase = .cleaning
            try commit(record)
            progress(OffloadProgress(stage: .cleaning, bytesDone: bytes, bytesTotal: bytes))
            let hidden = record.hiddenSourceURL
            try await runBlocking { _ in try FileManager.default.removeItem(at: hidden) }

            record.phase = .offloaded
            record.ferriedAt = Date()
            try commit(record)
            return record
        } catch is FaultInjector.Crash {
            throw FaultInjector.Crash()
        } catch {
            record.lastError = error.localizedDescription
            try? commit(record)
            _ = await recover(id)
            throw error
        }
    }

    private func swapInSymlink(_ record: OffloadRecord, copy: URL, fingerprint: String) throws {
        let original = record.originalURL
        try posixCheck(rename(original.path, record.hiddenSourceURL.path))
        try fault(.afterRenameSource)

        // Writes that landed between verification and the rename would be lost; put the original back.
        guard (try? TreeFingerprint.capture(record.hiddenSourceURL)) == fingerprint else {
            try posixCheck(rename(record.hiddenSourceURL.path, original.path))
            throw OffloadError.changedDuringOffload(record.originalPath)
        }
        try posixCheck(symlink(copy.path, original.path))
        try fault(.afterSymlink)
    }

    // MARK: - Move back

    public func moveBack(
        _ id: UUID, progress: @escaping @Sendable (OffloadProgress) -> Void = { _ in }
    ) async throws {
        guard var record = manifest.records.first(where: { $0.id == id }) else { throw OffloadError.recordNotFound }
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

        let staging = record.returnStagingURL
        record.phase = .returnCopying
        try commit(record)
        do {
            let faults = faults
            try await runBlocking { flag in
                var copier = TreeCopier(flag: flag) { progress(OffloadProgress(stage: .copying, bytesDone: $0, bytesTotal: bytes)) }
                copier.afterFile = { try faults?.hook(.returnCopiedFile($0)) }
                try copier.copy(from: copy, to: staging)
            }

            record.phase = .returnVerifying
            try commit(record)
            _ = try await runBlocking { flag in
                try TreeVerifier(flag: flag) { progress(OffloadProgress(stage: .verifying, bytesDone: $0, bytesTotal: bytes)) }
                    .verify(source: copy, copy: staging)
            }

            record.phase = .returnSwapping
            try commit(record)
            progress(OffloadProgress(stage: .swapping, bytesDone: bytes, bytesTotal: bytes))
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: record.originalPath)) == linkTarget else {
                throw OffloadError.brokenLink("\(record.originalPath) changed while moving it back.")
            }
            try posixCheck(unlink(record.originalPath))
            try fault(.afterRemoveSymlink)
            try posixCheck(rename(staging.path, record.originalPath))

            try fault(.beforeReturnCleanup)
            record.phase = .returnCleaning
            try commit(record)
            progress(OffloadProgress(stage: .cleaning, bytesDone: bytes, bytesTotal: bytes))
            let container = record.containerURL(mountPoint: mount)
            try await runBlocking { _ in try FileManager.default.removeItem(at: container) }
            try remove(record)
        } catch is FaultInjector.Crash {
            throw FaultInjector.Crash()
        } catch {
            record.lastError = error.localizedDescription
            try? commit(record)
            _ = await recover(id)
            throw error
        }
    }

    // MARK: - Maintenance

    public func status(of record: OffloadRecord) -> OffloadStatus {
        OffloadStatus.resolve(record, resolver: resolver)
    }

    /// Points the symlink at the drive's current mount point (e.g. after it remounted as "Backup 1").
    public func relink(_ id: UUID) throws {
        guard var record = manifest.records.first(where: { $0.id == id }), record.phase == .offloaded else {
            throw OffloadError.recordNotFound
        }
        guard let mount = resolver.mountPoint(forVolumeUUID: record.drive.volumeUUID) else {
            throw OffloadError.driveUnavailable(record.drive.name)
        }
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: record.originalPath)) != nil else {
            throw OffloadError.brokenLink("\(record.originalPath) is no longer a symlink.")
        }
        let temporary = record.originalURL.deletingLastPathComponent().appendingPathComponent(".\(record.name).charon-link")
        unlink(temporary.path)
        try posixCheck(symlink(record.copyURL(mountPoint: mount).path, temporary.path))
        try posixCheck(rename(temporary.path, record.originalPath))
        record.drive.mountPoint = mount
        try commit(record)
    }

    /// Drops a record without touching the filesystem. For entries the user resolved by hand.
    public func forget(_ id: UUID) throws {
        manifest.records.removeAll { $0.id == id }
        try store.save(manifest)
    }

    /// Resumes or rolls back every record that isn't at rest. Call on launch and when drives mount.
    @discardableResult
    public func reconcile() async -> [UUID: RecoveryOutcome] {
        var outcomes: [UUID: RecoveryOutcome] = [:]
        for record in manifest.records where !record.phase.isAtRest {
            outcomes[record.id] = await recover(record.id)
        }
        return outcomes
    }

    // MARK: - Journal

    func commit(_ record: OffloadRecord) throws {
        if let index = manifest.records.firstIndex(where: { $0.id == record.id }) {
            manifest.records[index] = record
        } else {
            manifest.records.append(record)
        }
        try store.save(manifest)
        mirror(to: record.drive)
    }

    func remove(_ record: OffloadRecord) throws {
        manifest.records.removeAll { $0.id == record.id }
        try store.save(manifest)
        mirror(to: record.drive)
    }

    func update(_ record: OffloadRecord) {
        try? commit(record)
    }

    func record(_ id: UUID) -> OffloadRecord? {
        manifest.records.first { $0.id == id }
    }

    var volumeResolver: any VolumeResolving { resolver }

    private func mirror(to drive: OffloadDrive) {
        guard let mount = resolver.mountPoint(forVolumeUUID: drive.volumeUUID) else { return }
        let records = manifest.records.filter { $0.drive.volumeUUID == drive.volumeUUID }
        let url = mount.appendingPathComponent(driveFolder).appendingPathComponent("manifest.plist")
        try? ManifestStore.write(OffloadManifest(records: records), to: url)
    }

    private func fault(_ point: FaultPoint) throws {
        try faults?.hook(point)
    }

    static func measure(_ url: URL) throws -> (bytes: Int64, files: Int64) {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            throw OffloadError.sourceMissing(url.path)
        }
        var bytes: Int64 = 0
        var files: Int64 = 0
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: keys)
            bytes += Int64(values?.totalFileAllocatedSize ?? 0)
            if values?.isRegularFile == true { files += 1 }
        }
        return (bytes, files)
    }
}
