// ViewModels/OffloadViewModel.swift
// Charon
//
// Offload records, their live status, the chosen External Drive, and the one operation that may run at a time.

import CharonKit
import Foundation
import Observation
import os

struct OffloadOperation: Identifiable {
    enum Kind { case offload, moveBack, check }

    let id = UUID()
    var kind: Kind
    var name: String
    var progress: OffloadProgress?
}

/// What the offload sheet shows: preflight, then progress, then the result.
struct OffloadRequest: Identifiable {
    enum Stage: Equatable { case checking, review, running, done(reclaimed: Int64), failed(String) }

    let id = UUID()
    var path: String
    var knownBytes: Int64?
    var report: PreflightReport?
    var stage: Stage = .checking
    var acknowledgedWarnings = false
}

@MainActor
@Observable
final class OffloadViewModel {
    private(set) var records: [OffloadRecord] = []
    private(set) var manifestProblem: String?
    private(set) var statuses: [UUID: OffloadStatus] = [:]
    private(set) var operation: OffloadOperation?
    private(set) var request: OffloadRequest?
    private(set) var alertMessage: String?
    private(set) var driveVolumeID: String? = UserDefaults.standard.string(forKey: AppSettings.driveVolumeID)

    /// Called with the original path after a successful offload.
    @ObservationIgnored var onOffloaded: ((String) -> Void)?

    @ObservationIgnored private let offloadEngine: OffloadEngine
    @ObservationIgnored private let preflight: OffloadPreflight
    @ObservationIgnored private var task: Task<Void, Never>?

    init(offloadEngine: OffloadEngine? = nil, preflight: OffloadPreflight? = nil) {
        self.offloadEngine = offloadEngine ?? OffloadEngine(
            store: ManifestStore(url: ManifestStore.defaultURL), driveFolder: AppSettings.driveFolderName
        )
        self.preflight = preflight ?? OffloadPreflight()
    }

    /// Sum of bytes living on other drives.
    var freedBytes: Int64 {
        records.filter { $0.phase == .offloaded }.reduce(0) { $0 + $1.bytes }
    }

    var disconnectedCount: Int {
        statuses.values.filter { $0 == .disconnected }.count
    }

    func status(of record: OffloadRecord) -> OffloadStatus {
        statuses[record.id] ?? .inProgress(record.phase)
    }

    func isOffloaded(_ path: String) -> Bool {
        records.contains { $0.originalPath == path }
    }

    // MARK: - Lifecycle

    /// Finishes or rolls back anything interrupted, then refreshes.
    func reconcile() async {
        let outcomes = await offloadEngine.reconcile()
        for (id, outcome) in outcomes {
            Logger.offload.info("Recovered \(id, privacy: .public): \(String(describing: outcome), privacy: .public)")
        }
        await refresh()
    }

    func refresh() async {
        manifestProblem = await offloadEngine.manifestProblem
        records = await offloadEngine.records.sorted { ($0.offloadedAt ?? $0.startedAt) > ($1.offloadedAt ?? $1.startedAt) }
        var next: [UUID: OffloadStatus] = [:]
        for record in records {
            next[record.id] = await offloadEngine.status(of: record)
        }
        statuses = next
    }

    func selectDrive(_ volumeID: String?) {
        driveVolumeID = volumeID
        UserDefaults.standard.set(volumeID, forKey: AppSettings.driveVolumeID)
    }

    func dismissAlert() {
        alertMessage = nil
    }

    // MARK: - Offload

    func requestOffload(path: String, knownBytes: Int64?, drive: VolumeInfo?) {
        guard operation == nil else {
            alertMessage = "Wait for the current crossing to finish."
            return
        }
        let userPath = OffloadPreflight.userFacingPath(path)
        request = OffloadRequest(path: userPath, knownBytes: knownBytes)
        let existing = records
        let preflight = preflight
        Task {
            let report = await preflight.check(
                source: URL(fileURLWithPath: userPath), drive: drive, bytes: knownBytes, existing: existing
            )
            guard request?.path == userPath else { return }
            request?.report = report
            request?.stage = .review
        }
    }

    func acknowledgeWarnings(_ value: Bool) {
        request?.acknowledgedWarnings = value
    }

    func dismissRequest() {
        guard request?.stage != .running else { return }
        request = nil
    }

    func confirmOffload(to driveVolume: VolumeInfo?) {
        guard var request, let report = request.report, report.canOffload,
              report.warnings.isEmpty || request.acknowledgedWarnings,
              let driveVolume, let drive = OffloadDrive(volume: driveVolume) else { return }
        request.stage = .running
        self.request = request
        let source = URL(fileURLWithPath: request.path)
        operation = OffloadOperation(kind: .offload, name: source.lastPathComponent)

        task = Task {
            do {
                let tracker = trackProgress()
                defer { tracker.finish() }
                let record = try await offloadEngine.offload(source, to: drive, progress: tracker.report)
                Logger.offload.info("Offloaded \(record.originalPath, privacy: .public)")
                self.request?.stage = .done(reclaimed: record.bytes)
                onOffloaded?(record.originalPath)
            } catch {
                Logger.offload.error("Offload failed: \(error.localizedDescription, privacy: .public)")
                self.request?.stage = .failed(error.localizedDescription)
            }
            operation = nil
            await refresh()
        }
    }

    /// Bridges engine progress (any thread) to `operation.progress`, keeping only the newest value.
    private func trackProgress() -> (report: @Sendable (OffloadProgress) -> Void, finish: () -> Void) {
        let (stream, continuation) = AsyncStream<OffloadProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        Task { [weak self] in
            for await progress in stream {
                self?.operation?.progress = progress
            }
        }
        return ({ continuation.yield($0) }, { continuation.finish() })
    }

    func cancelOperation() {
        task?.cancel()
    }

    // MARK: - Record actions

    func moveBack(_ record: OffloadRecord) {
        guard operation == nil else {
            alertMessage = "Wait for the current crossing to finish."
            return
        }
        operation = OffloadOperation(kind: .moveBack, name: record.name)
        task = Task {
            do {
                let tracker = trackProgress()
                defer { tracker.finish() }
                try await offloadEngine.moveBack(record.id, progress: tracker.report)
            } catch {
                alertMessage = error.localizedDescription
            }
            operation = nil
            await refresh()
        }
    }

    /// Reads every file of the copy back from the drive. Nothing is written.
    func checkCopy(_ record: OffloadRecord) {
        guard operation == nil else {
            alertMessage = "Wait for the current operation to finish."
            return
        }
        operation = OffloadOperation(kind: .check, name: record.name)
        task = Task {
            do {
                let tracker = trackProgress()
                defer { tracker.finish() }
                switch try await offloadEngine.checkCopy(record.id, progress: tracker.report) {
                case .intact:
                    alertMessage = "\(record.name) on \(record.drive.name) reads back intact."
                case .changedSinceOffload:
                    alertMessage = "\(record.name) reads back fine. Its contents changed since it was offloaded, which is expected if you edited it."
                case .unreadable(let path, let reason):
                    alertMessage = "\(record.name): \(path) couldn't be read (\(reason)). The drive may be failing; copy what you can."
                }
            } catch {
                alertMessage = error.localizedDescription
            }
            operation = nil
        }
    }

    func relink(_ record: OffloadRecord) {
        Task {
            do {
                try await offloadEngine.relink(record.id)
            } catch {
                alertMessage = error.localizedDescription
            }
            await refresh()
        }
    }

    func forget(_ record: OffloadRecord) {
        Task {
            try? await offloadEngine.forget(record.id)
            await refresh()
        }
    }
}
