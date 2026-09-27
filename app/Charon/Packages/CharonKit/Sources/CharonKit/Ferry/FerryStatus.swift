// Ferry/FerryStatus.swift
// CharonKit
//
// Live health of a ferried directory, derived from the manifest plus what's on disk right now.

import Foundation

public enum FerryStatus: Sendable, Hashable {
    /// Symlink points at a copy that's present.
    case ferried
    /// The shore isn't mounted; the symlink dangles until it's plugged back in.
    case stranded
    /// The shore is mounted at a different path than the symlink expects. Fixable with relink.
    case relocated(URL)
    /// Something changed outside Charon.
    case broken(String)
    case inProgress(FerryPhase)

    static func resolve(_ record: FerryRecord, resolver: any VolumeResolving) -> FerryStatus {
        guard record.phase == .ferried else { return .inProgress(record.phase) }
        guard let mount = resolver.mountPoint(forVolumeUUID: record.shore.volumeUUID) else { return .stranded }
        let copy = record.copyURL(mountPoint: mount)
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: record.originalPath) else {
            return .broken("\(record.originalPath) is no longer a symlink.")
        }
        guard FileManager.default.fileExists(atPath: copy.path) else {
            return .broken("The copy on \(record.shore.name) is missing.")
        }
        if URL(fileURLWithPath: target).standardizedFileURL.path != copy.standardizedFileURL.path {
            return .relocated(mount)
        }
        return .ferried
    }
}
