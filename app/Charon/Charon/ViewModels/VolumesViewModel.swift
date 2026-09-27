// ViewModels/VolumesViewModel.swift
// Charon
//
// Mounted volumes, refreshed when disks come and go.

import AppKit
import CharonKit
import Darwin
import Observation

@MainActor
@Observable
final class VolumesViewModel {
    private(set) var volumes: [VolumeInfo] = []
    /// Called after a mount/unmount so offload statuses can refresh.
    @ObservationIgnored var onChange: (() -> Void)?

    private let catalog = VolumeCatalog()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                    self?.onChange?()
                }
            })
        }
    }

    var bootVolume: VolumeInfo? { volumes.first(where: \.isBoot) }
    var driveCandidates: [VolumeInfo] { volumes.filter(\.canBeOffloadDrive) }

    func volume(_ id: String?) -> VolumeInfo? {
        guard let id else { return nil }
        return volumes.first { $0.id == id }
    }

    /// Matches the path's mount point against known volumes; cheap enough to call while rendering.
    func volumeContaining(_ path: String) -> VolumeInfo? {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return nil }
        let mount = withUnsafeBytes(of: &fs.f_mntonname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        if mount == "/" || mount == "/System/Volumes/Data" { return bootVolume }
        return volumes.first { $0.mountPoint.path == mount }
    }

    func refresh() {
        volumes = catalog.mountedVolumes()
    }

    func eject(_ volume: VolumeInfo) {
        try? NSWorkspace.shared.unmountAndEjectDevice(at: volume.mountPoint)
    }
}
