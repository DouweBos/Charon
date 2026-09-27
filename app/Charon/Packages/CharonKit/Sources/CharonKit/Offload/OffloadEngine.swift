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
    let store: ManifestStore
    let resolver: any VolumeResolving
    let faults: FaultInjector?
    private let driveFolder: String
    private var manifest: OffloadManifest
    /// Records with an operation running right now; `reconcile` must not touch them.
    var inFlight: Set<UUID> = []
    /// Set when the manifest exists but can't be read. All writes are refused so it isn't overwritten.
    public private(set) var manifestProblem: String?

    public init(
        store: ManifestStore, resolver: any VolumeResolving = VolumeCatalog(),
        driveFolder: String = "Charon", faults: FaultInjector? = nil
    ) {
        self.store = store
        self.resolver = resolver
        self.driveFolder = driveFolder
        self.faults = faults
        do {
            manifest = try store.load()
        } catch {
            manifest = OffloadManifest()
            manifestProblem = "The offload manifest at \(store.url.path) couldn't be read (\(error.localizedDescription)). "
                + "Charon won't change any offloads until it's fixed or moved aside."
        }
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
        // Baseline before copying: anything written after this point (even mid-verify) aborts the swap.
        let fingerprint = try await runBlocking { _ in try TreeFingerprint.capture(source) }
        guard !manifest.records.contains(where: { $0.originalPath == source.path }) else { throw OffloadError.recordBusy }
        let id = UUID()
        inFlight.insert(id)
        defer { inFlight.remove(id) }
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
            try await copyTree(from: source, to: copy, bytes: bytes, fault: FaultPoint.copiedFile, progress: progress)

            try fault(.beforeVerify)
            record.phase = .verifying
            try commit(record)
            record.treeDigest = try await verifyTree(source: source, copy: copy, bytes: bytes, progress: progress)
            guard (try? TreeFingerprint.capture(source)) == fingerprint else {
                throw OffloadError.changedDuringOffload(record.originalPath)
            }
            guard self.record(id)?.phase == .verifying, FileManager.default.fileExists(atPath: copy.path) else {
                throw OffloadError.verificationFailed(path: "/", reason: "the copy changed state while verifying")
            }

            progress(OffloadProgress(stage: .swapping, bytesDone: bytes, bytesTotal: bytes))
            record.phase = .swapping
            try commit(record)
            try swapInSymlink(record, copy: copy, fingerprint: fingerprint)

            try fault(.beforeCleanup)
            record.phase = .cleaning
            try commit(record)
            progress(OffloadProgress(stage: .cleaning, bytesDone: bytes, bytesTotal: bytes))
            let hidden = record.hiddenSourceURL
            try await runBlocking { _ in try Self.removeTree(hidden) }

            record.phase = .offloaded
            record.offloadedAt = Date()
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

    // MARK: - Steps

    func copyTree(
        from source: URL, to destination: URL, bytes: Int64, fault point: @escaping @Sendable (Int) -> FaultPoint,
        progress: @escaping @Sendable (OffloadProgress) -> Void
    ) async throws {
        let faults = faults
        try await runBlocking { flag in
            var copier = TreeCopier(flag: flag) { progress(OffloadProgress(stage: .copying, bytesDone: $0, bytesTotal: bytes)) }
            copier.afterFile = { try faults?.hook(point($0)) }
            try copier.copy(from: source, to: destination)
        }
    }

    func verifyTree(
        source: URL, copy: URL, bytes: Int64, progress: @escaping @Sendable (OffloadProgress) -> Void
    ) async throws -> String {
        try await runBlocking { flag in
            try TreeVerifier(flag: flag) { progress(OffloadProgress(stage: .verifying, bytesDone: $0, bytesTotal: bytes)) }
                .verify(source: source, copy: copy)
        }
    }

    // MARK: - Maintenance

    public enum CopyCheck: Sendable, Hashable {
        /// Every file read back and matches what was verified at offload time.
        case intact
        /// Every file is readable, but contents changed since the offload (edits made through the link).
        case changedSinceOffload
        case unreadable(path: String, reason: String)
    }

    /// Reads every byte of a record's copy on the drive. Read-only.
    public func checkCopy(
        _ id: UUID, progress: @escaping @Sendable (OffloadProgress) -> Void = { _ in }
    ) async throws -> CopyCheck {
        guard let record = record(id), record.phase == .offloaded else { throw OffloadError.recordNotFound }
        guard let mount = resolver.mountPoint(forVolumeUUID: record.drive.volumeUUID) else {
            throw OffloadError.driveUnavailable(record.drive.name)
        }
        let copy = record.copyURL(mountPoint: mount)
        let total = record.bytes
        do {
            let digest = try await runBlocking { flag in
                try TreeVerifier(flag: flag) { progress(OffloadProgress(stage: .verifying, bytesDone: $0 * 2, bytesTotal: total)) }
                    .digest(of: copy)
            }
            return digest == record.treeDigest ? .intact : .changedSinceOffload
        } catch CopyReadError.unreadable(let path, let reason) {
            return .unreadable(path: path, reason: reason)
        }
    }

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
        guard !inFlight.contains(id) else { throw OffloadError.recordBusy }
        try ensureWritable()
        manifest.records.removeAll { $0.id == id }
        try store.save(manifest)
    }

    /// Resumes or rolls back every record that isn't at rest. Call on launch and when drives mount.
    @discardableResult
    public func reconcile() async -> [UUID: RecoveryOutcome] {
        var outcomes: [UUID: RecoveryOutcome] = [:]
        for record in manifest.records where !record.phase.isAtRest && !inFlight.contains(record.id) {
            outcomes[record.id] = await recover(record.id)
        }
        return outcomes
    }

    // MARK: - Journal

    func commit(_ record: OffloadRecord) throws {
        try ensureWritable()
        if let index = manifest.records.firstIndex(where: { $0.id == record.id }) {
            manifest.records[index] = record
        } else {
            manifest.records.append(record)
        }
        try store.save(manifest)
        mirror(to: record.drive)
    }

    func remove(_ record: OffloadRecord) throws {
        try ensureWritable()
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

    private func ensureWritable() throws {
        if let manifestProblem { throw OffloadError.blocked([manifestProblem]) }
    }

    /// `removeItem` can't unlink children of read-only directories (Go's module cache, some toolchains),
    /// so make every directory writable first.
    static func removeTree(_ url: URL) throws {
        if let enumerator = FileManager.default.enumerator(atPath: url.path) {
            chmod(url.path, 0o700)
            for case let relative as String in enumerator {
                let path = url.path + "/" + relative
                var info = stat()
                if lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR {
                    chmod(path, (info.st_mode & 0o7777) | 0o700)
                }
            }
        }
        try FileManager.default.removeItem(at: url)
    }

    func fault(_ point: FaultPoint) throws {
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
