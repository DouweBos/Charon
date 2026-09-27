// ViewModels/OptimizeViewModel.swift
// Charon
//
// Background launch agents and daemons. Only your own agents can be removed; the rest is informational.

import AppKit
import CharonKit
import Observation
import os

@MainActor
@Observable
final class OptimizeViewModel {
    private(set) var items: [LaunchItem] = []
    private(set) var isLoading = false
    private(set) var pendingRemoval: LaunchItem?
    private(set) var message: String?

    var orphanCount: Int { items.filter(\.isOrphaned).count }

    func items(in scope: LaunchItem.Scope) -> [LaunchItem] {
        items.filter { $0.scope == scope }.sorted { ($0.isOrphaned ? 0 : 1, $0.label) < ($1.isOrphaned ? 0 : 1, $1.label) }
    }

    func loadIfNeeded() {
        guard items.isEmpty, !isLoading else { return }
        reload()
    }

    func reload() {
        isLoading = true
        Task {
            let running = await LaunchItemInventory.runningLabels()
            items = LaunchItemInventory().items(runningLabels: running)
            isLoading = false
        }
    }

    func requestRemoval(_ item: LaunchItem) {
        guard item.scope == .user else { return }
        pendingRemoval = item
    }

    func cancelRemoval() {
        pendingRemoval = nil
    }

    func dismissMessage() {
        message = nil
    }

    /// Stops the agent for this session, then moves its plist to the Trash so it doesn't start again.
    func confirmRemoval() {
        guard let item = pendingRemoval else { return }
        pendingRemoval = nil
        Task {
            await Self.bootOut(item)
            do {
                try await NSWorkspace.shared.recycle([item.url])
                message = "Removed \(item.label). Its plist is in the Trash."
            } catch {
                message = "Couldn't remove \(item.label): \(error.localizedDescription)"
            }
            reload()
        }
    }

    private static func bootOut(_ item: LaunchItem) async {
        let path = item.url.path
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["bootout", "gui/\(getuid())", path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }.value
    }
}
