// ViewModels/VolumesViewModel.swift
// Charon
//
// Mounted volumes, refreshed when disks come and go.

import AppKit
import CharonKit
import Observation

@MainActor
@Observable
final class VolumesViewModel {
    private(set) var volumes: [VolumeInfo] = []
    /// Called after a mount/unmount so ferry statuses can refresh.
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
    var shoreCandidates: [VolumeInfo] { volumes.filter(\.canBeShore) }

    func volume(_ id: String?) -> VolumeInfo? {
        guard let id else { return nil }
        return volumes.first { $0.id == id }
    }

    func volumeContaining(_ path: String) -> VolumeInfo? {
        guard let found = catalog.volume(containing: URL(fileURLWithPath: path)) else { return nil }
        return volumes.first { $0.id == found.id } ?? found
    }

    func refresh() {
        volumes = catalog.mountedVolumes()
    }

    func eject(_ volume: VolumeInfo) {
        try? NSWorkspace.shared.unmountAndEjectDevice(at: volume.mountPoint)
    }
}
