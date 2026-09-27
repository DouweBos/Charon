// Offload/OffloadStatus.swift
// CharonKit
//
// Live health of a offloaded directory, derived from the manifest plus what's on disk right now.

import Foundation

public enum OffloadStatus: Sendable, Hashable {
    /// Symlink points at a copy that's present.
    case offloaded
    /// The drive isn't mounted; the symlink dangles until it's plugged back in.
    case disconnected
    /// The drive is mounted at a different path than the symlink expects. Fixable with relink.
    case remounted(URL)
    /// Something changed outside Charon.
    case broken(String)
    case inProgress(OffloadPhase)

    static func resolve(_ record: OffloadRecord, resolver: any VolumeResolving) -> OffloadStatus {
        guard record.phase == .offloaded else { return .inProgress(record.phase) }
        guard let mount = resolver.mountPoint(forVolumeUUID: record.drive.volumeUUID) else { return .disconnected }
        let copy = record.copyURL(mountPoint: mount)
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: record.originalPath) else {
            return .broken("\(record.originalPath) is no longer a symlink.")
        }
        guard FileManager.default.fileExists(atPath: copy.path) else {
            return .broken("The copy on \(record.drive.name) is missing.")
        }
        if URL(fileURLWithPath: target).standardizedFileURL.path != copy.standardizedFileURL.path {
            return .remounted(mount)
        }
        return .offloaded
    }
}
