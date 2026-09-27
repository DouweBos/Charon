// ViewModels/AnalyzeViewModel.swift
// Charon
//
// Runs and holds one scan per volume. Views read the latest snapshot; the scan keeps streaming until done.
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

    func state(for volumeID: String?) -> ScanState? {
        volumeID.flatMap { scans[$0] }
    }

    /// Shows the archived scan if there is one, otherwise starts scanning.
    func scanIfNeeded(_ volume: VolumeInfo) {
        guard scans[volume.id] == nil else { return }
        guard UserDefaults.standard.bool(forKey: AppSettings.rememberScans) else {
            rescan(volume)
            return
        }
        let id = volume.id
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
                self.rescan(volume)
            }
        }
    }

    func rescan(_ volume: VolumeInfo) {
        tasks[volume.id]?.cancel()
        let id = volume.id
        let root = volume.scanRoot
        let displayRoot = volume.isBoot ? "/" : volume.mountPoint.path
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
