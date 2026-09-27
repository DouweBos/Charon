// Volumes/VolumeCatalog.swift
// CharonKit
//
// Enumerates mounted volumes and resolves volume UUIDs to mount points.

import Foundation

/// Resolves a volume UUID to where it's mounted right now. Injected so ferry tests can simulate unplugging.
public protocol VolumeResolving: Sendable {
    func mountPoint(forVolumeUUID uuid: String) -> URL?
    func volume(containing url: URL) -> VolumeInfo?
}

public struct VolumeCatalog: VolumeResolving {

    public init() {}

    private static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeLocalizedNameKey, .volumeUUIDStringKey, .volumeTotalCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeIsInternalKey,
        .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsReadOnlyKey, .volumeIsRootFileSystemKey,
        .volumeIsBrowsableKey, .volumeIsLocalKey
    ]

    /// Browsable local volumes, boot disk first.
    public func mountedVolumes() -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Self.keys, options: [.skipHiddenVolumes]) ?? []
        let volumes = urls.compactMap { info(for: $0) }.filter { $0.totalBytes > 0 }
        return volumes.sorted { lhs, rhs in
            if lhs.isBoot != rhs.isBoot { return lhs.isBoot }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    public func bootVolume() -> VolumeInfo? {
        info(for: URL(fileURLWithPath: "/"))
    }

    /// Includes hidden volumes: a shore mounted without Finder visibility is still the same shore.
    public func mountPoint(forVolumeUUID uuid: String) -> URL? {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeUUIDStringKey], options: []) ?? []
        return urls.first { (try? $0.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString == uuid }
    }

    public func volume(containing url: URL) -> VolumeInfo? {
        var fs = statfs()
        guard statfs(url.path, &fs) == 0 else { return nil }
        let mount = withUnsafeBytes(of: &fs.f_mntonname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        // The Data volume is part of the boot disk from the user's point of view.
        if mount == "/System/Volumes/Data" { return bootVolume() }
        return info(for: URL(fileURLWithPath: mount))
    }

    func info(for url: URL) -> VolumeInfo? {
        guard let values = try? url.resourceValues(forKeys: Set(Self.keys)) else { return nil }
        guard values.volumeIsLocal ?? true else { return nil }
        let isBoot = values.volumeIsRootFileSystem ?? (url.path == "/")
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let important = values.volumeAvailableCapacityForImportantUsage ?? 0
        let available = important > 0 ? important : Int64(values.volumeAvailableCapacity ?? 0)
        let name = values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent
        return VolumeInfo(
            id: values.volumeUUIDString ?? url.path,
            name: name,
            mountPoint: url,
            uuid: values.volumeUUIDString,
            totalBytes: total,
            availableBytes: available,
            fileSystem: Self.fileSystemType(at: url) ?? "unknown",
            isBoot: isBoot,
            isInternal: values.volumeIsInternal ?? isBoot,
            isEjectable: (values.volumeIsEjectable ?? false) || (values.volumeIsRemovable ?? false),
            isReadOnly: isBoot ? false : (values.volumeIsReadOnly ?? false)
        )
    }

    static func fileSystemType(at url: URL) -> String? {
        var fs = statfs()
        guard statfs(url.path, &fs) == 0 else { return nil }
        return withUnsafeBytes(of: &fs.f_fstypename) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }
}
