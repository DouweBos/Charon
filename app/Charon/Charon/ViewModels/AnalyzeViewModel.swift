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

    var isScanning: Bool { phase == .scanning }
}

@MainActor
@Observable
final class AnalyzeViewModel {
    private(set) var scans: [String: ScanState] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let archives = ScanArchiveStore()
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
            let archive = await Task.detached(priority: .userInitiated) { archives.load(volumeID: id) }.value
            guard let self, !Task.isCancelled else { return }
            if let archive {
                self.scans[id] = ScanState(
                    tree: archive.tree, progress: archive.progress, phase: .complete,
                    scannedAt: archive.scannedAt, isFromCache: true
                )
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

    func cancel(_ volumeID: String) {
        tasks[volumeID]?.cancel()
        tasks[volumeID] = nil
        if scans[volumeID]?.isScanning == true { scans[volumeID]?.phase = .cancelled }
    }

    /// Drops a ferried directory from the tree so the treemap reflects the freed space without a rescan.
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
            let files = update.progress.filesScanned
            Logger.scan.info("Scan done: \(files) files in \(update.progress.elapsed, privacy: .public)")
        }
        scans[id] = state
        if update.progress.isComplete { archive(id) }
    }

    private func archive(_ volumeID: String) {
        guard UserDefaults.standard.bool(forKey: AppSettings.rememberScans),
              let state = scans[volumeID], let tree = state.tree, state.phase == .complete else { return }
        let archive = ScanArchive(tree: tree, progress: state.progress, scannedAt: state.scannedAt ?? Date())
        let archives = archives
        Task.detached(priority: .utility) {
            do {
                try archives.save(archive, volumeID: volumeID)
            } catch {
                Logger.scan.error("Couldn't archive scan: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
