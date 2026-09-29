// ViewModels/CollectorViewModel.swift
// Charon
//
// Items gathered for removal. Confirmed items go to the Trash, or are deleted if Settings says so.

import AppKit
import CharonKit
import Observation
import os

@MainActor
@Observable
final class CollectorViewModel {
    enum Phase: Equatable {
        case idle
        /// Seconds left before removal starts.
        case countdown(Int)
        case removing(done: Int64, total: Int64, permanently: Bool)
    }

    static let countdownSeconds = 10

    private(set) var collected = CollectorSet()
    private(set) var phase = Phase.idle
    private(set) var message: String?
    /// Set after a successful move to the Trash, so the bar can offer to empty it.
    private(set) var canEmptyTrash = false

    /// Called with display paths that were moved to the Trash.
    @ObservationIgnored var onTrashed: (([String]) -> Void)?
    /// Checked when removal starts, since the countdown gives time for an offload to finish.
    @ObservationIgnored var offloadedPaths: () -> Set<String> = { [] }
    @ObservationIgnored private var countdownTask: Task<Void, Never>?

    var items: [CollectorSet.Item] { collected.items }
    var totalBytes: Int64 { collected.totalBytes }
    var isEmpty: Bool { collected.items.isEmpty }

    func contains(_ path: String) -> Bool {
        collected.contains(path)
    }

    /// Returns the refusal reason, if any, so callers can explain why nothing happened.
    func add(path: String, bytes: Int64, isDirectory: Bool, offloadedPaths: Set<String>) {
        if let refusal = TrashPolicy(offloadedPaths: offloadedPaths).refusal(for: path) {
            message = refusal
            return
        }
        collected.add(CollectorSet.Item(path: path, bytes: bytes, isDirectory: isDirectory))
    }

    func remove(_ path: String) {
        collected.remove(path)
    }

    func clear() {
        collected.removeAll()
    }

    /// Starts the countdown; removal begins when it runs out unless cancelled.
    func requestRemoval() {
        guard !isEmpty, phase == .idle else { return }
        message = nil
        countdownTask = Task {
            for remaining in stride(from: Self.countdownSeconds, to: 0, by: -1) {
                phase = .countdown(remaining)
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }
            remove()
        }
    }

    func cancelRemoval() {
        guard case .countdown = phase else { return }
        countdownTask?.cancel()
        countdownTask = nil
        phase = .idle
    }

    func dismissMessage() {
        message = nil
        canEmptyTrash = false
    }

    func showMessage(_ text: String) {
        message = text
        canEmptyTrash = false
    }

    func trashEmptied() {
        message = "Emptied the Trash."
        canEmptyTrash = false
    }

    /// Re-checks every item: something collected earlier may have been offloaded since.
    private func remove() {
        let policy = TrashPolicy(offloadedPaths: offloadedPaths())
        let refused = collected.items.filter { policy.refusal(for: $0.path) != nil }
        for item in refused { collected.remove(item.path) }
        let items = collected.items
        let permanently = FileRemoval.deletesPermanently
        let total = collected.totalBytes
        phase = .removing(done: 0, total: total, permanently: permanently)
        Task {
            defer { phase = .idle }
            let (progress, reporter) = AsyncStream<Int64>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let watcher = Task {
                for await done in progress {
                    phase = .removing(done: min(done, total), total: total, permanently: permanently)
                    // Deleting reports every file; redrawing for each would starve the main thread.
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            var trashed: [String] = []
            var failures: [String] = []
            var finished: Int64 = 0
            for item in items {
                let base = finished
                do {
                    try await FileRemoval.remove([URL(fileURLWithPath: item.path)], permanently: permanently) { bytes in
                        reporter.yield(base + min(bytes, item.bytes))
                    }
                    trashed.append(item.path)
                } catch {
                    Logger.volumes.error("Removal failed for \(item.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    failures.append((item.path as NSString).lastPathComponent)
                }
                finished += item.bytes
                reporter.yield(finished)
            }
            reporter.finish()
            await watcher.value
            // Detach from the scan before un-collecting, so removed items never flash back onto the map.
            onTrashed?(trashed)
            for path in trashed { collected.remove(path) }
            let freed = items.filter { trashed.contains($0.path) }.reduce(Int64(0)) { $0 + $1.bytes }
            failures += refused.map { ($0.path as NSString).lastPathComponent }
            canEmptyTrash = !permanently && !trashed.isEmpty
            if !failures.isEmpty {
                let names = failures.joined(separator: ", ")
                message = permanently ? "Couldn't delete \(names)." : "Couldn't move \(names) to the Trash."
            } else {
                message = permanently
                    ? "Deleted \(ByteSize.format(freed))."
                    : "Moved \(ByteSize.format(freed)) to the Trash. Empty the Trash to free the space."
            }
        }
    }
}
