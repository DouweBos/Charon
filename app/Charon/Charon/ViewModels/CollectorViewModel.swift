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
    func add(path: String, bytes: Int64, isDirectory: Bool, ferriedPaths: Set<String>) {
        if let refusal = TrashPolicy(ferriedPaths: ferriedPaths).refusal(for: path) {
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
    }

    func confirmTrash() {
        isConfirming = false
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
            message = failures.isEmpty
                ? "Moved \(ByteSize.format(freed)) to the Trash. Empty the Trash to free the space."
                : "Couldn't move \(failures.joined(separator: ", ")) to the Trash."
        }
    }
}
