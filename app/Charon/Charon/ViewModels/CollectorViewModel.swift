// ViewModels/CollectorViewModel.swift
// Charon
//
// Items gathered for removal. Nothing is deleted: confirmed items go to the Trash.

import AppKit
import CharonKit
import Observation
import os

@MainActor
@Observable
final class CollectorViewModel {
    private(set) var collected = CollectorSet()
    private(set) var isTrashing = false
    private(set) var message: String?
    /// Set after a successful move to the Trash, so the bar can offer to empty it.
    private(set) var canEmptyTrash = false
    private(set) var isConfirming = false

    /// Called with display paths that were moved to the Trash.
    @ObservationIgnored var onTrashed: (([String]) -> Void)?

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

    func requestTrash() {
        guard !isEmpty else { return }
        isConfirming = true
    }

    func cancelTrash() {
        isConfirming = false
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
    func confirmTrash(offloadedPaths: Set<String>) {
        isConfirming = false
        let policy = TrashPolicy(offloadedPaths: offloadedPaths)
        let refused = collected.items.filter { policy.refusal(for: $0.path) != nil }
        for item in refused { collected.remove(item.path) }
        let items = collected.items
        isTrashing = true
        Task {
            defer { isTrashing = false }
            var trashed: [String] = []
            var failures: [String] = []
            for item in items {
                do {
                    try await NSWorkspace.shared.recycle([URL(fileURLWithPath: item.path)])
                    trashed.append(item.path)
                    collected.remove(item.path)
                } catch {
                    Logger.volumes.error("Trash failed for \(item.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    failures.append((item.path as NSString).lastPathComponent)
                }
            }
            onTrashed?(trashed)
            let freed = items.filter { trashed.contains($0.path) }.reduce(Int64(0)) { $0 + $1.bytes }
            failures += refused.map { ($0.path as NSString).lastPathComponent }
            canEmptyTrash = !trashed.isEmpty
            message = failures.isEmpty
                ? "Moved \(ByteSize.format(freed)) to the Trash. Empty the Trash to free the space."
                : "Couldn't move \(failures.joined(separator: ", ")) to the Trash."
        }
    }
}
