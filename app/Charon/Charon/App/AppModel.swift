// App/AppModel.swift
// Charon
//
// Owns the navigator and every ViewModel, and wires them together so views stay thin.

import CharonKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let navigator = AppNavigator()
    let volumes = VolumesViewModel()
    let analyze = AnalyzeViewModel()
    let ferry = FerryViewModel()
    let stats = StatsViewModel()
    private(set) var hasFullDiskAccess = SystemIntegration.hasFullDiskAccess
    private(set) var dismissedAccessBanner = false

    init() {
        navigator.setDefaultVolume(volumes.bootVolume?.id)
        volumes.onChange = { [weak self] in self?.volumesChanged() }
        ferry.onFerried = { [weak self] path in self?.ferried(path) }
        Task { await ferry.reconcile() }
    }

    var currentVolume: VolumeInfo? {
        volumes.volume(navigator.volumeID) ?? volumes.bootVolume
    }

    var shoreVolume: VolumeInfo? {
        volumes.volume(ferry.shoreVolumeID)
    }

    var currentScan: ScanState? {
        analyze.state(for: currentVolume?.id)
    }

    /// The drilled-into node, falling back to the root while a scan hasn't reached it yet.
    var focusNode: DiskTree.NodeID {
        guard let tree = currentScan?.tree, let path = navigator.focusPath else { return DiskTree.root }
        return tree.node(atDisplayPath: path) ?? DiskTree.root
    }

    /// Used space the finished scan couldn't see; shown as "System & other" at the volume root.
    var unaccountedBytes: Int64 {
        guard let scan = currentScan, scan.phase == .complete, let tree = scan.tree,
              focusNode == DiskTree.root, let volume = currentVolume else { return 0 }
        return max(volume.usedBytes - tree.size(DiskTree.root), 0)
    }

    func focus(_ node: DiskTree.NodeID) {
        guard let tree = currentScan?.tree else { return }
        navigator.focus(node == DiskTree.root ? nil : tree.displayPath(node))
    }

    /// Goes up, skipping wrapper folders that only contain the folder we came from.
    func focusParent() {
        guard let tree = currentScan?.tree, var parent = tree.parent(focusNode) else { return }
        while parent != DiskTree.root, tree.children(parent).count == 1, let next = tree.parent(parent) {
            parent = next
        }
        focus(parent)
    }

    func startCurrentScan() {
        guard let volume = currentVolume else { return }
        analyze.scanIfNeeded(volume)
    }

    func rescanCurrent() {
        guard let volume = currentVolume else { return }
        analyze.rescan(volume)
    }

    func requestFerry(path: String, knownBytes: Int64?) {
        ferry.requestFerry(path: path, knownBytes: knownBytes, shore: shoreVolume)
    }

    func recheckFullDiskAccess() {
        hasFullDiskAccess = SystemIntegration.hasFullDiskAccess
    }

    func dismissAccessBanner() {
        dismissedAccessBanner = true
    }

    private func volumesChanged() {
        if navigator.volumeID != nil, volumes.volume(navigator.volumeID) == nil {
            navigator.setDefaultVolume(volumes.bootVolume?.id)
        }
        Task { await ferry.reconcile() }
    }

    private func ferried(_ path: String) {
        analyze.detach(displayPath: path)
        volumes.refresh()
    }
}
