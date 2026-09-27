// ViewModels/FerryViewModel.swift
// Charon
//
// Ferry records, their live status, the chosen Other Shore, and the one operation that may run at a time.

import CharonKit
import Foundation
import Observation
import os

struct FerryOperation: Identifiable {
    enum Kind { case ferry, bringHome }

    let id = UUID()
    var kind: Kind
    var name: String
    var progress: FerryProgress?
}

/// What the ferry sheet shows: preflight, then progress, then the result.
struct FerryRequest: Identifiable {
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
final class FerryViewModel {
    private(set) var records: [FerryRecord] = []
    private(set) var statuses: [UUID: FerryStatus] = [:]
    private(set) var operation: FerryOperation?
    private(set) var request: FerryRequest?
    private(set) var errorMessage: String?
    private(set) var shoreVolumeID: String? = UserDefaults.standard.string(forKey: AppSettings.shoreVolumeID)

    /// Called with the original path after a successful ferry.
    @ObservationIgnored var onFerried: ((String) -> Void)?

    @ObservationIgnored private let ferryman: Ferryman
    @ObservationIgnored private let preflight: FerryPreflight
    @ObservationIgnored private var task: Task<Void, Never>?

    init(ferryman: Ferryman? = nil, preflight: FerryPreflight? = nil) {
        self.ferryman = ferryman ?? Ferryman(
            store: ManifestStore(url: ManifestStore.defaultURL), shoreFolder: AppSettings.shoreFolderName
        )
        self.preflight = preflight ?? FerryPreflight()
    }

    /// Sum of bytes living on other shores.
    var obols: Int64 {
        records.filter { $0.phase == .ferried }.reduce(0) { $0 + $1.bytes }
    }

    var strandedCount: Int {
        statuses.values.filter { $0 == .stranded }.count
    }

    func status(of record: FerryRecord) -> FerryStatus {
        statuses[record.id] ?? .inProgress(record.phase)
    }

    func isFerried(_ path: String) -> Bool {
        records.contains { $0.originalPath == path }
    }

    // MARK: - Lifecycle

    /// Finishes or rolls back anything interrupted, then refreshes.
    func reconcile() async {
        let outcomes = await ferryman.reconcile()
        for (id, outcome) in outcomes {
            Logger.ferry.info("Recovered \(id, privacy: .public): \(String(describing: outcome), privacy: .public)")
        }
        await refresh()
    }

    func refresh() async {
        records = await ferryman.records.sorted { ($0.ferriedAt ?? $0.startedAt) > ($1.ferriedAt ?? $1.startedAt) }
        var next: [UUID: FerryStatus] = [:]
        for record in records {
            next[record.id] = await ferryman.status(of: record)
        }
        statuses = next
    }

    func selectShore(_ volumeID: String?) {
        shoreVolumeID = volumeID
        UserDefaults.standard.set(volumeID, forKey: AppSettings.shoreVolumeID)
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Ferry

    func requestFerry(path: String, knownBytes: Int64?, shore: VolumeInfo?) {
        guard operation == nil else {
            errorMessage = "Wait for the current crossing to finish."
            return
        }
        let userPath = FerryPreflight.userFacingPath(path)
        request = FerryRequest(path: userPath, knownBytes: knownBytes)
        let existing = records
        let preflight = preflight
        Task {
            let report = await preflight.check(
                source: URL(fileURLWithPath: userPath), shore: shore, bytes: knownBytes, existing: existing
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

    func confirmFerry(to shoreVolume: VolumeInfo?) {
        guard var request, let report = request.report, report.canFerry,
              report.warnings.isEmpty || request.acknowledgedWarnings,
              let shoreVolume, let shore = Shore(volume: shoreVolume) else { return }
        request.stage = .running
        self.request = request
        let source = URL(fileURLWithPath: request.path)
        operation = FerryOperation(kind: .ferry, name: source.lastPathComponent)

        task = Task {
            do {
                let tracker = trackProgress()
                defer { tracker.finish() }
                let record = try await ferryman.ferry(source, to: shore, progress: tracker.report)
                Logger.ferry.info("Ferried \(record.originalPath, privacy: .public)")
                self.request?.stage = .done(reclaimed: record.bytes)
                onFerried?(record.originalPath)
            } catch {
                Logger.ferry.error("Ferry failed: \(error.localizedDescription, privacy: .public)")
                self.request?.stage = .failed(error.localizedDescription)
            }
            operation = nil
            await refresh()
        }
    }

    /// Bridges engine progress (any thread) to `operation.progress`, keeping only the newest value.
    private func trackProgress() -> (report: @Sendable (FerryProgress) -> Void, finish: () -> Void) {
        let (stream, continuation) = AsyncStream<FerryProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
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

    func bringHome(_ record: FerryRecord) {
        guard operation == nil else {
            errorMessage = "Wait for the current crossing to finish."
            return
        }
        operation = FerryOperation(kind: .bringHome, name: record.name)
        task = Task {
            do {
                let tracker = trackProgress()
                defer { tracker.finish() }
                try await ferryman.bringHome(record.id, progress: tracker.report)
            } catch {
                errorMessage = error.localizedDescription
            }
            operation = nil
            await refresh()
        }
    }

    func relink(_ record: FerryRecord) {
        Task {
            do {
                try await ferryman.relink(record.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            await refresh()
        }
    }

    func forget(_ record: FerryRecord) {
        Task {
            try? await ferryman.forget(record.id)
            await refresh()
        }
    }
}
