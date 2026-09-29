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
    private(set) var isConfirmingEmptyTrash = false
    /// Size of the user's Trash, or nil until measured (or when it can't be read without Full Disk Access).
    private(set) var trashBytes: Int64?
    @ObservationIgnored private var trashTask: Task<Void, Never>?
    /// Folders every scan skips, as user-facing paths.
    private(set) var excludedPaths: [String] = UserDefaults.standard.stringArray(forKey: AppSettings.excludedPaths) ?? []

    init() {
        navigator.setDefaultTarget(volumes.bootVolume?.id)
        volumes.onChange = { [weak self] in self?.volumesChanged() }
        offload.onOffloaded = { [weak self] path in self?.offloaded(path) }
        collector.onTrashed = { [weak self] paths in self?.trashed(paths) }
        collector.offloadedPaths = { [weak self] in Set(self?.offload.records.map(\.originalPath) ?? []) }
        clean.onTrashed = { [weak self] paths in self?.trashed(paths) }
        clean.repositories = { [weak self] in
            guard let self, let boot = self.volumes.bootVolume, let tree = self.analyze.state(for: boot.id)?.tree else { return nil }
            return GitWorktreeFinder.repositories(in: tree)
        }
        Task { await offload.reconcile() }
        HistoryGestures.install(back: { [weak self] in self?.goBack() }, forward: { [weak self] in self?.goForward() })
        refreshTrash()
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
        analyze.state(for: currentTarget?.id, hiding: Set(collector.items.map(\.path)))
    }

    /// Everything the current scan found, including collected items the map already leaves out.
    var scannedBytes: Int64 {
        analyze.state(for: currentTarget?.id)?.tree?.size(DiskTree.root) ?? 0
    }

    /// The drilled-into node, falling back to the root while a scan hasn't reached it yet.
    var focusNode: DiskTree.NodeID {
        guard let tree = currentScan?.tree, let path = navigator.focusPath else { return DiskTree.root }
        return tree.node(atDisplayPath: path) ?? DiskTree.root
    }

    /// Used space the finished scan couldn't see; shown as "System & other" at the volume root.
    var unaccountedBytes: Int64 {
        guard let scan = currentScan, scan.phase == .complete,
              focusNode == DiskTree.root, currentTarget?.isFolder == false, let volume = currentVolume else { return 0 }
        return max(volume.usedBytes - scannedBytes, 0)
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

    /// With no history yet (a folder opened from the menu bar), back goes to the enclosing folder.
    var canGoBack: Bool {
        navigator.canGoBack || (navigator.tab == .analyze && focusNode != DiskTree.root)
    }

    func goBack() {
        if navigator.canGoBack { navigator.goBack() } else if canGoBack { focusParent() }
    }

    func goForward() {
        navigator.goForward()
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

    /// Folders opened with Charon (the menu bar monitor, the Dock icon) are shown in their disk's scan.
    func open(_ urls: [URL]) {
        guard let url = urls.first,
              let volume = volumes.volumeContaining(url.path) else { return }
        navigator.reveal(OffloadPreflight.userFacingPath(url.standardizedFileURL.path), in: volume.id)
        startCurrentScan()
    }

    /// Opens a folder from elsewhere in the app (Clean, Uninstall) in its disk's Map or Rings.
    func showInAnalyze(_ url: URL, mode: AnalyzeMode) {
        guard let volume = volumes.volumeContaining(url.path) else { return }
        let path = OffloadPreflight.userFacingPath(url.standardizedFileURL.path)
        if url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            navigator.show(path, in: volume.id, mode: mode)
        } else {
            navigator.reveal(path, in: volume.id)
        }
        startCurrentScan()
    }

    func isInCurrentScan(_ url: URL) -> Bool {
        currentScan?.tree?.node(atDisplayPath: OffloadPreflight.userFacingPath(url.standardizedFileURL.path)) != nil
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
        // The map's sizes leave out what's already collected, but adding a folder absorbs those items.
        let scan = analyze.state(for: currentTarget?.id)?.tree
        let bytes = scan.flatMap { tree in tree.node(atDisplayPath: path).map(tree.size) } ?? bytes
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

    func refreshTrash() {
        trashTask?.cancel()
        trashTask = Task {
            let url = URL(fileURLWithPath: SystemIntegration.trashPath)
            let readable = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
            let bytes = readable ? try? await CleanMeasurer.size(of: url) : nil
            guard !Task.isCancelled else { return }
            trashBytes = bytes
        }
    }

    func requestEmptyTrash() {
        isConfirmingEmptyTrash = true
    }

    func cancelEmptyTrash() {
        isConfirmingEmptyTrash = false
    }

    func confirmEmptyTrash() {
        isConfirmingEmptyTrash = false
        if let error = SystemIntegration.emptyTrash() {
            clean.showMessage("Finder couldn't empty the Trash: \(error)")
            collector.showMessage("Finder couldn't empty the Trash: \(error)")
            return
        }
        collector.trashEmptied()
        // The scan saw the Trash's old contents; drop them so the map matches.
        if let tree = currentScan?.tree, let trash = tree.node(atDisplayPath: SystemIntegration.trashPath) {
            for child in tree.children(trash) { analyze.detach(displayPath: tree.displayPath(child)) }
        }
        volumes.refresh()
        refreshTrash()
        if clean.hasMeasured { clean.measure() }
    }

    private func trashed(_ paths: [String]) {
        for path in paths { analyze.detach(displayPath: path) }
        volumes.refresh()
        refreshTrash()
    }

    private func offloaded(_ path: String) {
        analyze.detach(displayPath: path)
        volumes.refresh()
    }
}
