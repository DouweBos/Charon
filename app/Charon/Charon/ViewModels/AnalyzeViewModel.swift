// ViewModels/AnalyzeViewModel.swift
// Charon
//
// Runs and holds one scan per target (volume or folder). Views read the latest snapshot; the scan keeps streaming until done.
// Finished scans are archived so the next launch opens on the last result.

import CharonKit
import Foundation
import Observation
import os

struct ScanState {
    enum Phase: Equatable { case scanning, complete, cancelled, failed(String) }

    var tree: DiskTree?
    var progress = ScanProgress()
    var phase: Phase = .scanning
    /// When the shown tree was completed; set for finished and cached scans.
    var scannedAt: Date?
    var isFromCache = false
    /// Scanned by the root helper, so restricted folders are included.
    var isAdministrator = false

    var isScanning: Bool { phase == .scanning }
}

@MainActor
@Observable
final class AnalyzeViewModel {
    private(set) var scans: [String: ScanState] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let archives = ScanArchiveStore()
    /// The finished tree a running rescan will be compared against.
    @ObservationIgnored private var adminRequests: [String: AdminScanRequest] = [:]
    @ObservationIgnored private var baselines: [String: (tree: DiskTree, date: Date)] = [:]
    /// Recently scanned folders, newest first.
    private(set) var folderPaths: [String] = UserDefaults.standard.stringArray(forKey: AppSettings.recentFolders) ?? []

    func addFolder(_ path: String) {
        folderPaths = Array(([path] + folderPaths.filter { $0 != path }).prefix(8))
        UserDefaults.standard.set(folderPaths, forKey: AppSettings.recentFolders)
    }

    func removeFolder(_ path: String) {
        folderPaths.removeAll { $0 == path }
        UserDefaults.standard.set(folderPaths, forKey: AppSettings.recentFolders)
    }

    func state(for targetID: String?) -> ScanState? {
        targetID.flatMap { scans[$0] }
    }

    /// Shows the archived scan if there is one, otherwise starts scanning.
    func scanIfNeeded(_ target: ScanTarget) {
        guard scans[target.id] == nil else { return }
        guard UserDefaults.standard.bool(forKey: AppSettings.rememberScans) else {
            rescan(target)
            return
        }
        let id = target.id
        let archives = archives
        scans[id] = ScanState()
        tasks[id] = Task { [weak self] in
            let (archive, previous) = await Task.detached(priority: .userInitiated) {
                (archives.load(volumeID: id), archives.loadPrevious(volumeID: id))
            }.value
            guard let self, !Task.isCancelled else { return }
            if let archive {
                self.scans[id] = ScanState(
                    tree: archive.tree, progress: archive.progress, phase: .complete,
                    scannedAt: archive.scannedAt, isFromCache: true
                )
                if let previous {
                    self.comparisons[id] = ScanComparison(previous: previous.tree, current: archive.tree, previousDate: previous.scannedAt)
                }
            } else {
                self.rescan(target)
            }
        }
    }

    func rescan(_ target: ScanTarget) {
        tasks[target.id]?.cancel()
        let id = target.id
        let root = target.root
        let displayRoot = target.displayRoot
        if let finished = scans[id], finished.phase == .complete, let tree = finished.tree {
            baselines[id] = (tree, finished.scannedAt ?? Date())
        }
        scans[id] = ScanState()
        Logger.scan.info("Scanning \(root.path, privacy: .public)")

        tasks[id] = Task { [weak self] in
            let stream = DiskScanner(options: AppSettings.scanOptions).scan(root: root, displayRootPath: displayRoot)
            do {
                for try await update in stream {
                    self?.apply(update, to: id)
                }
            } catch is CancellationError {
                self?.scans[id]?.phase = .cancelled
            } catch {
                self?.scans[id]?.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Runs the bundled scanner as root after the system password prompt; progress comes from its progress file.
    func rescanAsAdministrator(_ target: ScanTarget) {
        tasks[target.id]?.cancel()
        let id = target.id
        let previous = scans[id]
        if let previous, previous.phase == .complete, let tree = previous.tree {
            baselines[id] = (tree, previous.scannedAt ?? Date())
        }
        let directory: URL
        do {
            directory = try AdminScanRunner.makeOutputDirectory()
        } catch {
            scans[id] = ScanState(phase: .failed(error.localizedDescription))
            return
        }
        let options = AppSettings.scanOptions
        let request = AdminScanRequest(
            root: target.root.path, displayRoot: target.displayRoot, outputDirectory: directory.path,
            ownerUID: getuid(), largeFileThreshold: options.largeFileThreshold,
            excludedPaths: UserDefaults.standard.stringArray(forKey: AppSettings.excludedPaths) ?? []
        )
        adminRequests[id] = request
        var state = previous ?? ScanState()
        state.phase = .scanning
        state.isAdministrator = true
        scans[id] = state

        tasks[id] = Task { [weak self] in
            let poller = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    if let progress = AdminScanOutput.readProgress(request.progressPath) { self?.scans[id]?.progress = progress }
                }
            }
            defer {
                poller.cancel()
                try? FileManager.default.removeItem(at: directory)
            }
            do {
                try await AdminScanRunner.run(request)
                let archive = try await Task.detached {
                    try ScanArchive.decode(Data(contentsOf: URL(fileURLWithPath: request.resultPath)))
                }.value
                self?.finishAdministratorScan(archive, for: id)
            } catch {
                guard let self else { return }
                self.baselines[id] = nil
                if case AdminScanRunner.RunError.declined = error, let previous {
                    self.scans[id] = previous
                } else {
                    self.scans[id]?.phase = self.adminRequests[id] == nil ? .cancelled : .failed(error.localizedDescription)
                }
            }
            self?.adminRequests[id] = nil
        }
    }

    private func finishAdministratorScan(_ archive: ScanArchive, for id: String) {
        var progress = archive.progress
        progress.isComplete = true
        apply(ScanUpdate(tree: archive.tree, progress: progress), to: id)
        scans[id]?.isAdministrator = true
    }

    func cancel(_ volumeID: String) {
        if let request = adminRequests.removeValue(forKey: volumeID) {
            FileManager.default.createFile(atPath: request.cancelPath, contents: nil)
        }
        tasks[volumeID]?.cancel()
        tasks[volumeID] = nil
        if scans[volumeID]?.isScanning == true { scans[volumeID]?.phase = .cancelled }
    }

    /// Previous scan versus the current one, per target, once there are two to compare.
    private(set) var comparisons: [String: ScanComparison] = [:]

    /// Folders being rescanned on their own, by display path.
    private(set) var refreshingPaths: Set<String> = []

    /// Rescans one folder and splices the result in, so a change doesn't need a full disk scan.
    func rescanFolder(displayPath: String, in targetID: String) {
        guard let state = scans[targetID], !state.isScanning, let tree = state.tree,
              let node = tree.node(atDisplayPath: displayPath), tree.isDirectory(node),
              !refreshingPaths.contains(displayPath) else { return }
        let root = URL(fileURLWithPath: tree.realPath(node))
        refreshingPaths.insert(displayPath)
        Task { [weak self] in
            var fresh: DiskTree?
            do {
                for try await update in DiskScanner(options: AppSettings.scanOptions).scan(root: root, displayRootPath: displayPath) {
                    fresh = update.tree
                }
            } catch {
                Logger.scan.error("Folder rescan failed: \(error.localizedDescription, privacy: .public)")
            }
            guard let self else { return }
            self.refreshingPaths.remove(displayPath)
            guard let fresh, var current = self.scans[targetID]?.tree,
                  let target = current.node(atDisplayPath: displayPath) else { return }
            current.graft(fresh, at: target)
            self.scans[targetID]?.tree = current
            self.archive(targetID)
        }
    }

    /// Drops an offloaded directory from the tree so the treemap reflects the freed space without a rescan.
    func detach(displayPath: String) {
        for (volumeID, state) in scans where !state.isScanning {
            guard var tree = state.tree, let node = tree.node(atDisplayPath: displayPath) else { continue }
            tree.detach(node)
            scans[volumeID]?.tree = tree
            archive(volumeID)
        }
    }

    private func apply(_ update: ScanUpdate, to id: String) {
        var state = scans[id] ?? ScanState()
        state.tree = update.tree
        state.progress = update.progress
        if update.progress.isComplete {
            state.phase = .complete
            state.scannedAt = Date()
            if let baseline = baselines.removeValue(forKey: id) {
                comparisons[id] = ScanComparison(previous: baseline.tree, current: update.tree, previousDate: baseline.date)
            }
            let files = update.progress.filesScanned
            Logger.scan.info("Scan done: \(files) files in \(update.progress.elapsed, privacy: .public)")
        }
        scans[id] = state
        if update.progress.isComplete { archive(id, isNewScan: true) }
    }

    private func archive(_ volumeID: String, isNewScan: Bool = false) {
        guard UserDefaults.standard.bool(forKey: AppSettings.rememberScans),
              let state = scans[volumeID], let tree = state.tree, state.phase == .complete else { return }
        let archive = ScanArchive(tree: tree, progress: state.progress, scannedAt: state.scannedAt ?? Date())
        let archives = archives
        Task.detached(priority: .utility) {
            do {
                try archives.save(archive, volumeID: volumeID, keepPrevious: isNewScan)
            } catch {
                Logger.scan.error("Couldn't archive scan: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
