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
    let hiddenSpace = HiddenSpaceViewModel()
    let collector = CollectorViewModel()
    private(set) var hasFullDiskAccess = SystemIntegration.hasFullDiskAccess
    private(set) var dismissedAccessBanner = false

    init() {
        navigator.setDefaultTarget(volumes.bootVolume?.id)
        volumes.onChange = { [weak self] in self?.volumesChanged() }
        ferry.onFerried = { [weak self] path in self?.ferried(path) }
        collector.onTrashed = { [weak self] paths in self?.trashed(paths) }
        Task { await ferry.reconcile() }
        if !hasFullDiskAccess, !UserDefaults.standard.bool(forKey: AppSettings.accessPromptShown) {
            UserDefaults.standard.set(true, forKey: AppSettings.accessPromptShown)
            navigator.present(.fullDiskAccess)
        }
    }

    /// Volumes first, then recently scanned folders.
    var targets: [ScanTarget] {
        volumes.volumes.map(ScanTarget.volume) + analyze.folderPaths.map { path in
            ScanTarget.folder(URL(fileURLWithPath: path), volume: volumes.volumeContaining(path))
        }
    }

    var currentTarget: ScanTarget? {
        targets.first { $0.id == navigator.targetID } ?? volumes.bootVolume.map(ScanTarget.volume)
    }

    /// The scanned volume, or the one holding the scanned folder.
    var currentVolume: VolumeInfo? {
        currentTarget?.volume ?? volumes.bootVolume
    }

    var shoreVolume: VolumeInfo? {
        volumes.volume(ferry.shoreVolumeID)
    }

    var currentScan: ScanState? {
        analyze.state(for: currentTarget?.id)
    }

    /// The drilled-into node, falling back to the root while a scan hasn't reached it yet.
    var focusNode: DiskTree.NodeID {
        guard let tree = currentScan?.tree, let path = navigator.focusPath else { return DiskTree.root }
        return tree.node(atDisplayPath: path) ?? DiskTree.root
    }

    /// Used space the finished scan couldn't see; shown as "System & other" at the volume root.
    var unaccountedBytes: Int64 {
        guard let scan = currentScan, scan.phase == .complete, let tree = scan.tree,
              focusNode == DiskTree.root, currentTarget?.isFolder == false, let volume = currentVolume else { return 0 }
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
        guard let target = currentTarget else { return }
        analyze.scanIfNeeded(target)
    }

    func rescanCurrent() {
        guard let target = currentTarget else { return }
        analyze.rescan(target)
    }

    func scanFolder(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        let target = ScanTarget.folder(url, volume: volumes.volumeContaining(url.path))
        analyze.addFolder(target.root.path)
        navigator.selectTarget(target.id)
    }

    func chooseFolderToScan() {
        if let url = SystemIntegration.chooseDirectory(message: "Choose a folder to scan.") {
            scanFolder(url)
        }
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
        if navigator.targetID != nil, !targets.contains(where: { $0.id == navigator.targetID }) {
            navigator.setDefaultTarget(volumes.bootVolume?.id)
        }
        Task { await ferry.reconcile() }
    }

    func collect(path: String, bytes: Int64, isDirectory: Bool) {
        collector.add(path: path, bytes: bytes, isDirectory: isDirectory, ferriedPaths: Set(ferry.records.map(\.originalPath)))
    }

    private func trashed(_ paths: [String]) {
        for path in paths { analyze.detach(displayPath: path) }
        volumes.refresh()
    }

    private func ferried(_ path: String) {
        analyze.detach(displayPath: path)
        volumes.refresh()
    }
}
