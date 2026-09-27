// Offload/OffloadRecord.swift
// CharonKit
//
// One offloaded directory in the manifest. The phase is the journal: it's saved before each step so an
// interrupted operation can be resumed or rolled back.

import Foundation

public enum OffloadPhase: String, Codable, Sendable, Hashable {
    case copying
    case verifying
    case swapping
    case cleaning
    case offloaded
    case returnCopying
    case returnVerifying
    case returnSwapping
    case returnCleaning

    public var isAtRest: Bool { self == .offloaded }
    public var isReturning: Bool {
        [.returnCopying, .returnVerifying, .returnSwapping, .returnCleaning].contains(self)
    }
}

/// The drive a record lives on. Identified by volume UUID because mount paths change ("Backup" → "Backup 1").
public struct OffloadDrive: Codable, Sendable, Hashable {
    public var volumeUUID: String
    public var name: String
    public var mountPoint: URL

    public init(volumeUUID: String, name: String, mountPoint: URL) {
        self.volumeUUID = volumeUUID
        self.name = name
        self.mountPoint = mountPoint
    }

    public init?(volume: VolumeInfo) {
        guard let uuid = volume.uuid else { return nil }
        self.init(volumeUUID: uuid, name: volume.name, mountPoint: volume.mountPoint)
    }
}

public struct OffloadRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// Where the directory lived and where the symlink now is.
    public var originalPath: String
    public var drive: OffloadDrive
    /// Location of the copy relative to the drive's mount point.
    public var driveRelativePath: String
    public var bytes: Int64
    public var fileCount: Int64
    public var phase: OffloadPhase
    public var startedAt: Date
    public var offloadedAt: Date?
    /// SHA-256 over every file's relative path and content digest, recorded at verification.
    public var treeDigest: String?
    public var lastError: String?

    public var name: String { (originalPath as NSString).lastPathComponent }
    public var originalURL: URL { URL(fileURLWithPath: originalPath) }

    /// The directory on the drive that holds this record's copy (`Charon/<id>`).
    public var driveContainerRelativePath: String { (driveRelativePath as NSString).deletingLastPathComponent }

    var shortID: String { String(id.uuidString.prefix(8)).lowercased() }

    /// Sibling the original is renamed to during the swap, so it can be restored until the copy is live.
    var hiddenSourceURL: URL {
        originalURL.deletingLastPathComponent().appendingPathComponent(".\(name).charon-\(shortID)")
    }

    /// Staging directory on the home disk while moving a directory back.
    var returnStagingURL: URL {
        originalURL.deletingLastPathComponent().appendingPathComponent(".\(name).charon-return-\(shortID)")
    }

    func copyURL(mountPoint: URL) -> URL {
        mountPoint.appendingPathComponent(driveRelativePath)
    }

    func containerURL(mountPoint: URL) -> URL {
        mountPoint.appendingPathComponent(driveContainerRelativePath)
    }
}
