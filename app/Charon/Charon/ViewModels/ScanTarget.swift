// ViewModels/ScanTarget.swift
// Charon
//
// Something that can be scanned: a whole volume or a folder the user picked.

import CharonKit
import Foundation

struct ScanTarget: Identifiable, Hashable {
    var id: String
    var name: String
    var root: URL
    var displayRoot: String
    /// The volume itself, or the volume holding the folder.
    var volume: VolumeInfo?
    var isFolder: Bool

    static func volume(_ volume: VolumeInfo) -> ScanTarget {
        ScanTarget(
            id: volume.id, name: volume.name, root: volume.scanRoot,
            displayRoot: volume.isBoot ? "/" : volume.mountPoint.path, volume: volume, isFolder: false
        )
    }

    static func folder(_ url: URL, volume: VolumeInfo?) -> ScanTarget {
        let path = OffloadPreflight.userFacingPath(url.standardizedFileURL.path)
        return ScanTarget(
            id: "folder:" + path, name: (path as NSString).lastPathComponent, root: URL(fileURLWithPath: path),
            displayRoot: path, volume: volume, isFolder: true
        )
    }

    var symbol: String {
        if isFolder { return "folder" }
        return volume?.isBoot == true ? "internaldrive" : "externaldrive"
    }
}
