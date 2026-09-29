// ViewModels/UninstallViewModel.swift
// Charon
//
// Apps with their sizes and leftovers. Uninstalling trashes (or deletes) the app and chosen leftovers.

import AppKit
import CharonKit
import Observation
import os

@MainActor
@Observable
final class UninstallViewModel {
    private(set) var apps: [InstalledApp] = []
    private(set) var isLoading = false
    private(set) var selectedAppID: String?
    private(set) var leftovers: [AppLeftover] = []
    private(set) var isLoadingLeftovers = false
    private(set) var removing: Set<String> = []
    private(set) var isConfirming = false
    private(set) var isUninstalling = false
    private(set) var message: String?
    private(set) var query = ""

    @ObservationIgnored private let inventory = AppInventory()
    @ObservationIgnored private var leftoverTask: Task<Void, Never>?

    var filteredApps: [InstalledApp] {
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) }
    }

    var selectedApp: InstalledApp? { apps.first { $0.id == selectedAppID } }

    var removalBytes: Int64 {
        (selectedApp?.bytes ?? 0) + leftovers.filter { removing.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }

    var isSelectedAppRunning: Bool {
        guard let app = selectedApp else { return false }
        return NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL == app.url.standardizedFileURL }
    }

    func setQuery(_ text: String) {
        query = text
    }

    func loadIfNeeded() {
        guard apps.isEmpty, !isLoading else { return }
        reload()
    }

    func reload() {
        isLoading = true
        let inventory = inventory
        Task {
            apps = await inventory.apps()
            isLoading = false
            if selectedApp == nil { selectedAppID = nil }
        }
    }

    func select(_ id: String?) {
        selectedAppID = id
        leftovers = []
        removing = []
        leftoverTask?.cancel()
        guard let app = selectedApp else { return }
        isLoadingLeftovers = true
        let inventory = inventory
        leftoverTask = Task {
            let found = await inventory.leftovers(for: app)
            guard !Task.isCancelled, selectedAppID == app.id else { return }
            leftovers = found
            removing = Set(found.filter { !$0.isUncertain }.map(\.id))
            isLoadingLeftovers = false
        }
    }

    func isRemoving(_ id: String) -> Bool {
        removing.contains(id)
    }

    func toggleLeftover(_ id: String) {
        if removing.contains(id) { removing.remove(id) } else { removing.insert(id) }
    }

    func requestUninstall() {
        guard selectedApp != nil, !isSelectedAppRunning else { return }
        isConfirming = true
    }

    func cancelUninstall() {
        isConfirming = false
    }

    func dismissMessage() {
        message = nil
    }

    func confirmUninstall() {
        isConfirming = false
        guard let app = selectedApp else { return }
        let urls = [app.url] + leftovers.filter { removing.contains($0.id) }.map(\.url)
        let permanently = FileRemoval.deletesPermanently
        isUninstalling = true
        Task {
            defer { isUninstalling = false }
            var failed: [String] = []
            for url in urls {
                do {
                    try await FileRemoval.remove([url], permanently: permanently)
                } catch {
                    Logger.volumes.error("Uninstall skipped \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    failed.append(url.lastPathComponent)
                }
            }
            let names = failed.joined(separator: ", ")
            switch (failed.isEmpty, permanently) {
            case (true, true): message = "Deleted \(app.name) and \(urls.count - 1) leftovers."
            case (true, false): message = "Moved \(app.name) and \(urls.count - 1) leftovers to the Trash."
            case (false, true): message = "Couldn't delete \(names)."
            case (false, false): message = "Couldn't move \(names) to the Trash."
            }
            if !failed.contains(app.url.lastPathComponent) {
                apps.removeAll { $0.id == app.id }
                select(nil)
            }
        }
    }
}
