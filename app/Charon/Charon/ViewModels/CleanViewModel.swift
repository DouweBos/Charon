// ViewModels/CleanViewModel.swift
// Charon
//
// Measures the clean catalog and moves the chosen categories' contents to the Trash.

import AppKit
import CharonKit
import Observation
import os

@MainActor
@Observable
final class CleanViewModel {
    struct Row: Identifiable {
        var category: CleanCategory
        var items: [CleanItem]?
        var error: String?

        var id: String { category.id }
        var bytes: Int64 { items?.reduce(0) { $0 + $1.bytes } ?? 0 }
        var hasItems: Bool { !(items ?? []).isEmpty }
        var isMeasured: Bool { items != nil || error != nil }
        /// Where the category lives on disk: the folder whose contents it clears, or the items themselves.
        var locations: [URL] {
            guard let items else { return [] }
            guard category.mode == .contents else { return items.map(\.url) }
            var seen = Set<String>()
            return items.map { $0.url.deletingLastPathComponent() }.filter { seen.insert($0.path).inserted }
        }
    }

    private(set) var rows: [Row] = CleanCatalog.all.map { Row(category: $0) }
    private(set) var selection: Set<String> = Set(CleanCatalog.all.filter { $0.safety == .regenerated }.map(\.id))
    /// Chosen items in categories where the user picks items, keyed by item id.
    private(set) var selectedItems: Set<String> = []
    private(set) var isMeasuring = false
    private(set) var isCleaning = false
    private(set) var isConfirming = false
    private(set) var message: String?

    /// Called with paths moved to the Trash, so scans can drop them.
    @ObservationIgnored var onTrashed: (([String]) -> Void)?
    /// Git repositories from the startup disk scan, or nil when there's no scan yet.
    @ObservationIgnored var repositories: (() -> [String]?)?
    @ObservationIgnored private var worktreeRepositories: [String: String] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let measurer = CleanMeasurer()

    var selectedBytes: Int64 {
        rows.reduce(0) { $0 + selectedItems(in: $1).reduce(0) { $0 + $1.bytes } }
    }

    /// Whether the selection includes simulators, which `simctl` deletes outright rather than trashing.
    var deletesSimulators: Bool {
        rows.contains { $0.category.mode == .simulators && !selectedItems(in: $0).isEmpty }
    }

    var hasMeasured: Bool { rows.contains(where: \.isMeasured) }

    func rows(in group: CleanCategory.Group) -> [Row] {
        rows.filter { $0.category.group == group }
    }

    func isSelected(_ id: String) -> Bool {
        selection.contains(id)
    }

    func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func isItemSelected(_ item: CleanItem) -> Bool {
        selectedItems.contains(item.id)
    }

    func setItem(_ item: CleanItem, selected: Bool) {
        if selected { selectedItems.insert(item.id) } else { selectedItems.remove(item.id) }
    }

    /// What cleaning would take from the row: its picked items, or everything when the whole category is selected.
    func selectedItems(in row: Row) -> [CleanItem] {
        guard row.category.mode != .emptyTrash, let items = row.items else { return [] }
        if row.category.picksItems { return items.filter { selectedItems.contains($0.id) } }
        return selection.contains(row.id) ? items : []
    }

    func measureIfNeeded() {
        guard !hasMeasured, !isMeasuring else { return }
        measure()
    }

    func measure() {
        task?.cancel()
        isMeasuring = true
        rows = CleanCatalog.all.map { Row(category: $0) }
        let measurer = measurer
        let repositories = repositories?()
        task = Task {
            defer { isMeasuring = false }
            for category in CleanCatalog.all {
                guard !Task.isCancelled else { return }
                if category.mode == .gitWorktrees {
                    await measureWorktrees(category, repositories: repositories)
                    continue
                }
                do {
                    let items = try await measurer.measure(category)
                    update(category.id) { $0.items = items }
                } catch {
                    update(category.id) { $0.error = error.localizedDescription }
                }
            }
        }
    }

    func requestClean() {
        guard selectedBytes > 0 else { return }
        isConfirming = true
    }

    func cancelClean() {
        isConfirming = false
    }

    func dismissMessage() {
        message = nil
    }

    func confirmClean() {
        isConfirming = false
        let simulators = rows.filter { $0.category.mode == .simulators }.flatMap(selectedItems(in:))
        let items = rows.filter { $0.category.mode != .simulators }.flatMap(selectedItems(in:))
        guard !items.isEmpty || !simulators.isEmpty else { return }
        let permanently = FileRemoval.deletesPermanently
        isCleaning = true
        Task {
            defer { isCleaning = false }
            var trashed: [String] = []
            var deleted: [String] = []
            for item in items {
                do {
                    try await FileRemoval.remove([item.url] + item.companions, permanently: permanently)
                    trashed.append(item.url.path)
                } catch {
                    Logger.volumes.error("Clean skipped \(item.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            for simulator in simulators {
                if await SimulatorDevices.delete(simulator.url.lastPathComponent) {
                    deleted.append(simulator.url.path)
                } else {
                    Logger.volumes.error("simctl couldn't delete \(simulator.url.path, privacy: .public)")
                }
            }
            // Removed worktrees still have entries in their repository; let git drop them.
            let repositories = Set(trashed.compactMap { worktreeRepositories[$0] })
            for repository in repositories { await GitWorktreeFinder().prune(repository) }
            message = Self.summary(
                removed: trashed.count, permanently: permanently, deleted: deleted.count,
                skipped: items.count + simulators.count - trashed.count - deleted.count
            )
            onTrashed?(trashed + deleted)
            measure()
        }
    }

    private static func summary(removed: Int, permanently: Bool, deleted: Int, skipped: Int) -> String {
        var parts: [String] = []
        if removed > 0 { parts.append(permanently ? "Deleted \(removed) items" : "Moved \(removed) items to the Trash") }
        if deleted > 0 { parts.append("deleted \(deleted) simulators") }
        if skipped > 0 { parts.append("skipped \(skipped) in use or protected") }
        let sentence = parts.joined(separator: ", ")
        let text = sentence.prefix(1).uppercased() + sentence.dropFirst() + "."
        return removed > 0 && !permanently ? text + " Empty the Trash to free the space." : text
    }

    func showMessage(_ text: String) {
        message = text
    }

    private func measureWorktrees(_ category: CleanCategory, repositories: [String]?) async {
        guard let repositories else {
            update(category.id) { $0.error = "Scan the startup disk in Analyze first; that's where repositories are found." }
            return
        }
        let finder = GitWorktreeFinder()
        var items: [CleanItem] = []
        for repository in repositories {
            guard !Task.isCancelled else { return }
            for worktree in await finder.staleWorktrees(in: repository) {
                worktreeRepositories[worktree.path] = repository
                let repositoryName = (repository as NSString).lastPathComponent
                let detail = [worktree.branch, worktree.reason, repositoryName].compactMap { $0 }.joined(separator: " · ")
                items.append(CleanItem(url: URL(fileURLWithPath: worktree.path), bytes: worktree.bytes, detail: detail))
            }
        }
        update(category.id) { $0.items = items.sorted { $0.bytes > $1.bytes } }
    }

    private func update(_ id: String, _ change: (inout Row) -> Void) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        change(&rows[index])
    }
}
