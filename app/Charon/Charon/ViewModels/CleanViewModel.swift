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
        var isMeasured: Bool { items != nil || error != nil }
    }

    private(set) var rows: [Row] = CleanCatalog.all.map { Row(category: $0) }
    private(set) var selection: Set<String> = Set(CleanCatalog.all.filter { $0.safety == .regenerated }.map(\.id))
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
        rows.filter { selection.contains($0.id) && $0.category.mode != .emptyTrash }.reduce(0) { $0 + $1.bytes }
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
        let targets = rows.filter { selection.contains($0.id) && $0.category.mode != .emptyTrash }
        let urls = targets.flatMap { $0.items ?? [] }.map(\.url)
        guard !urls.isEmpty else { return }
        isCleaning = true
        Task {
            defer { isCleaning = false }
            var trashed: [String] = []
            for url in urls {
                do {
                    try await NSWorkspace.shared.recycle([url])
                    trashed.append(url.path)
                } catch {
                    Logger.volumes.error("Clean skipped \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            // Worktrees moved to the Trash still have entries in their repository; let git drop them.
            let repositories = Set(trashed.compactMap { worktreeRepositories[$0] })
            for repository in repositories { await GitWorktreeFinder().prune(repository) }
            let skipped = urls.count - trashed.count
            message = "Moved \(trashed.count) items to the Trash" + (skipped > 0 ? ", skipped \(skipped) in use or protected." : ".")
                + " Empty the Trash to free the space."
            onTrashed?(trashed)
            measure()
        }
    }

    /// Finder shows its own confirmation, so nothing is deleted without the user agreeing there too.
    func emptyTrash() {
        let script = NSAppleScript(source: "tell application \"Finder\" to empty trash")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error {
            message = "Finder couldn't empty the Trash: \(error[NSAppleScript.errorMessage] as? String ?? "unknown error")"
        }
        measure()
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
