// Volumes/VolumeInfo.swift
// CharonKit
//
// A mounted volume as Charon sees it: capacity, identity, and where to scan.

import Foundation

public struct VolumeInfo: Sendable, Hashable, Identifiable, Codable {
    /// Volume UUID when available, otherwise the mount path.
    public var id: String
    public var name: String
    public var mountPoint: URL
    public var uuid: String?
    public var totalBytes: Int64
    public var availableBytes: Int64
    /// Space macOS can free on demand (local snapshots, caches); counted as available.
    public var purgeableBytes: Int64 = 0
    public var fileSystem: String
    public var isBoot: Bool
    public var isInternal: Bool
    public var isEjectable: Bool
    public var isReadOnly: Bool

    public init(
        id: String, name: String, mountPoint: URL, uuid: String?, totalBytes: Int64, availableBytes: Int64,
        fileSystem: String, isBoot: Bool, isInternal: Bool, isEjectable: Bool, isReadOnly: Bool
    ) {
        self.id = id
        self.name = name
        self.mountPoint = mountPoint
        self.uuid = uuid
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.fileSystem = fileSystem
        self.isBoot = isBoot
        self.isInternal = isInternal
        self.isEjectable = isEjectable
        self.isReadOnly = isReadOnly
    }

    public var usedBytes: Int64 { max(totalBytes - availableBytes, 0) }

    /// On the boot disk the firmlinked user data lives on the Data volume; scanning "/" would hit the sealed system volume.
    public var scanRoot: URL {
        if isBoot {
            let data = URL(fileURLWithPath: "/System/Volumes/Data")
            if FileManager.default.fileExists(atPath: data.path) { return data }
        }
        return mountPoint
    }

    /// Shores need to hold arbitrary directories and not be the disk we're freeing.
    public var canBeShore: Bool { !isBoot && !isReadOnly }

    /// exFAT/FAT drop POSIX permissions, ACLs and xattrs.
    public var preservesMetadata: Bool {
        ["apfs", "hfs"].contains(fileSystem.lowercased())
    }
}
