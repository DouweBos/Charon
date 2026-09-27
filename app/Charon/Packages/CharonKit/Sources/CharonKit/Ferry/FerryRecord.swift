// Ferry/FerryRecord.swift
// CharonKit
//
// One ferried directory in the manifest. The phase is the journal: it's saved before each step so an
// interrupted operation can be resumed or rolled back.

import Foundation

public enum FerryPhase: String, Codable, Sendable, Hashable {
    case copying
    case verifying
    case swapping
    case cleaning
    case ferried
    case returnCopying
    case returnVerifying
    case returnSwapping
    case returnCleaning

    public var isAtRest: Bool { self == .ferried }
    public var isReturning: Bool {
        [.returnCopying, .returnVerifying, .returnSwapping, .returnCleaning].contains(self)
    }
}

/// The drive a record lives on. Identified by volume UUID because mount paths change ("Shore" → "Shore 1").
public struct Shore: Codable, Sendable, Hashable {
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

public struct FerryRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// Where the directory lived and where the symlink now is.
    public var originalPath: String
    public var shore: Shore
    /// Location of the copy relative to the shore's mount point.
    public var shoreRelativePath: String
    public var bytes: Int64
    public var fileCount: Int64
    public var phase: FerryPhase
    public var startedAt: Date
    public var ferriedAt: Date?
    /// SHA-256 over every file's relative path and content digest, recorded at verification.
    public var treeDigest: String?
    public var lastError: String?

    public var name: String { (originalPath as NSString).lastPathComponent }
    public var originalURL: URL { URL(fileURLWithPath: originalPath) }

    /// The directory on the shore that holds this record's copy (`Charon/<id>`).
    public var shoreContainerRelativePath: String { (shoreRelativePath as NSString).deletingLastPathComponent }

    var shortID: String { String(id.uuidString.prefix(8)).lowercased() }

    /// Sibling the original is renamed to during the swap, so it can be restored until the copy is live.
    var hiddenSourceURL: URL {
        originalURL.deletingLastPathComponent().appendingPathComponent(".\(name).charon-\(shortID)")
    }

    /// Staging directory on the home disk while bringing a directory home.
    var returnStagingURL: URL {
        originalURL.deletingLastPathComponent().appendingPathComponent(".\(name).charon-return-\(shortID)")
    }

    func copyURL(mountPoint: URL) -> URL {
        mountPoint.appendingPathComponent(shoreRelativePath)
    }

    func containerURL(mountPoint: URL) -> URL {
        mountPoint.appendingPathComponent(shoreContainerRelativePath)
    }
}
