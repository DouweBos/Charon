// App/AppModel.swift
// Charon
//
// Owns the navigator and every ViewModel, and wires them together so views stay thin.

import AppKit
import CharonKit
import UniformTypeIdentifiers
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let navigator = AppNavigator()
    let volumes = VolumesViewModel()
    let analyze = AnalyzeViewModel()
    let offload = OffloadViewModel()
    let hiddenSpace = HiddenSpaceViewModel()
    let collector = CollectorViewModel()
    let clean = CleanViewModel()
    let uninstall = UninstallViewModel()
    let optimize = OptimizeViewModel()
    let duplicates = DuplicatesViewModel()
    private(set) var hasFullDiskAccess = SystemIntegration.hasFullDiskAccess
    private(set) var dismissedAccessBanner = false
    /// Folders every scan skips, as user-facing paths.
    private(set) var excludedPaths: [String] = UserDefaults.standard.stringArray(forKey: AppSettings.excludedPaths) ?? []

    init() {
        navigator.setDefaultTarget(volumes.bootVolume?.id)
        volumes.onChange = { [weak self] in self?.volumesChanged() }
        offload.onOffloaded = { [weak self] path in self?.offloaded(path) }
        collector.onTrashed = { [weak self] paths in self?.trashed(paths) }
        clean.onTrashed = { [weak self] paths in self?.trashed(paths) }
        clean.repositories = { [weak self] in
            guard let self, let boot = self.volumes.bootVolume, let tree = self.analyze.state(for: boot.id)?.tree else { return nil }
            return GitWorktreeFinder.repositories(in: tree)
        }
        Task { await offload.reconcile() }
        MonitorLoginItem.enableOnFirstLaunch()
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

    var driveVolume: VolumeInfo? {
        volumes.volume(offload.driveVolumeID)
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

    var currentComparison: ScanComparison? {
        currentTarget.flatMap { analyze.comparisons[$0.id] }
    }

    /// Offloaded folders that used to live directly in the drilled-into folder.
    var offloadedHere: [OffloadRecord] {
        guard let tree = currentScan?.tree else { return [] }
        let here = tree.displayPath(focusNode)
        return offload.records.filter { record in
            record.phase == .offloaded && (record.originalPath as NSString).deletingLastPathComponent == here
        }
    }

    var hasBootScan: Bool {
        volumes.bootVolume.flatMap { analyze.state(for: $0.id)?.tree } != nil
    }

    /// Largest safe-to-move folders in the home directory, from the startup disk scan.
    var offloadSuggestions: [OffloadSuggestion] {
        guard let boot = volumes.bootVolume, let tree = analyze.state(for: boot.id)?.tree else { return [] }
        return OffloadSuggester().suggestions(in: tree, existing: offload.records)
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

    func exclude(_ path: String) {
        let path = OffloadPreflight.userFacingPath(path)
        guard !excludedPaths.contains(path) else { return }
        excludedPaths.append(path)
        excludedPaths.sort()
        UserDefaults.standard.set(excludedPaths, forKey: AppSettings.excludedPaths)
        analyze.detach(displayPath: path)
    }

    func removeExclusion(_ path: String) {
        excludedPaths.removeAll { $0 == path }
        UserDefaults.standard.set(excludedPaths, forKey: AppSettings.excludedPaths)
    }

    func chooseExclusion() {
        if let url = SystemIntegration.chooseDirectory(message: "Choose a folder for scans to skip.") {
            exclude(url.path)
        }
    }

    func exportCurrentFolder() {
        guard let tree = currentScan?.tree else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(tree.name(focusNode).replacingOccurrences(of: "/", with: "-")).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? tree.csv(childrenOf: focusNode).write(to: url, atomically: true, encoding: .utf8)
    }

    func rescanFolder(_ displayPath: String) {
        guard let target = currentTarget else { return }
        analyze.rescanFolder(displayPath: displayPath, in: target.id)
    }

    func rescanCurrent() {
        guard let target = currentTarget else { return }
        analyze.rescan(target)
    }

    func rescanCurrentAsAdministrator() {
        guard let target = currentTarget else { return }
        analyze.rescanAsAdministrator(target)
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

    func requestOffload(path: String, knownBytes: Int64?) {
        offload.requestOffload(path: path, knownBytes: knownBytes, drive: driveVolume)
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
        Task { await offload.reconcile() }
    }

    func collect(path: String, bytes: Int64, isDirectory: Bool) {
        collector.add(path: path, bytes: bytes, isDirectory: isDirectory, offloadedPaths: Set(offload.records.map(\.originalPath)))
    }

    /// Items dragged onto the Collector, sized from the current scan when it has them.
    func collectDropped(_ urls: [URL]) {
        for url in urls {
            let path = OffloadPreflight.userFacingPath(url.standardizedFileURL.path)
            let tree = currentScan?.tree
            let node = tree?.node(atDisplayPath: path)
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            collect(path: path, bytes: node.flatMap { tree?.size($0) } ?? 0, isDirectory: isDirectory.boolValue)
        }
    }

    func trashCollected() {
        collector.confirmTrash(offloadedPaths: Set(offload.records.map(\.originalPath)))
    }

    private func trashed(_ paths: [String]) {
        for path in paths { analyze.detach(displayPath: path) }
        volumes.refresh()
    }

    private func offloaded(_ path: String) {
        analyze.detach(displayPath: path)
        volumes.refresh()
    }
}
