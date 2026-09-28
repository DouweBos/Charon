// Cleanup/GitWorktrees.swift
// CharonKit
//
// Finds linked git worktrees whose work already landed in the repository's default branch and that have no
// uncommitted changes: removing them loses nothing. Git is run with optional locks off so looking never
// rewrites the index.

import Foundation

public struct GitWorktree: Sendable, Hashable {
    public var path: String
    public var head: String?
    public var branch: String?
    public var isMain: Bool
    public var isBare: Bool
    public var isLocked: Bool
    public var isPrunable: Bool
}

public struct StaleWorktree: Sendable, Hashable, Identifiable {
    public var path: String
    public var repository: String
    public var branch: String?
    public var reason: String
    public var bytes: Int64
    public var id: String { path }
}

public enum GitWorktreeParser {
    /// Parses `git worktree list --porcelain`. The first entry is the main worktree.
    // swiftlint:disable:next cyclomatic_complexity
    public static func parse(_ output: String) -> [GitWorktree] {
        var worktrees: [GitWorktree] = []
        var current: GitWorktree?
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty {
                if let finished = current { worktrees.append(finished) }
                current = nil
                continue
            }
            let parts = line.split(separator: " ", maxSplits: 1)
            let key = String(parts[0])
            let value = parts.count > 1 ? String(parts[1]) : ""
            switch key {
            case "worktree":
                if let finished = current { worktrees.append(finished) }
                current = GitWorktree(path: value, head: nil, branch: nil, isMain: worktrees.isEmpty,
                                      isBare: false, isLocked: false, isPrunable: false)
            case "HEAD": current?.head = value
            case "branch": current?.branch = value.replacingOccurrences(of: "refs/heads/", with: "")
            case "bare": current?.isBare = true
            case "locked": current?.isLocked = true
            case "prunable": current?.isPrunable = true
            default: break
            }
        }
        if let finished = current { worktrees.append(finished) }
        return worktrees
    }
}

public struct GitWorktreeFinder: Sendable {
    public var git: String

    public init(git: String = "/usr/bin/git") {
        self.git = git
    }

    /// Repositories in a scan: folders holding a `.git` directory, outside Library and package folders.
    public static func repositories(in tree: DiskTree) -> [String] {
        var repositories: [String] = []
        for index in 0..<tree.nodeCount {
            let node = DiskTree.NodeID(index)
            guard tree.name(node) == ".git", tree.isDirectory(node), let parent = tree.parent(node), tree.isAttached(node) else { continue }
            let path = tree.realPath(parent)
            if path.contains("/node_modules/") || path.contains("/Library/") || path.contains("/.Trash/") { continue }
            repositories.append(path)
        }
        return repositories.sorted()
    }

    /// Linked worktrees of `repository` that are clean and fully contained in its default branch.
    public func staleWorktrees(in repository: String) async -> [StaleWorktree] {
        guard let listing = await run(["-C", repository, "worktree", "list", "--porcelain"]),
              let base = await defaultBranch(repository) else { return [] }
        var stale: [StaleWorktree] = []
        for worktree in GitWorktreeParser.parse(listing) {
            guard !worktree.isMain, !worktree.isBare, !worktree.isLocked, !worktree.isPrunable,
                  let head = worktree.head, FileManager.default.fileExists(atPath: worktree.path) else { continue }
            // Anything uncommitted (including untracked, non-ignored files) is work that would be lost.
            guard let status = await run(["-C", worktree.path, "status", "--porcelain"]), status.isEmpty else { continue }
            guard let reason = await mergeReason(head: head, base: base, repository: repository) else { continue }
            let bytes = (try? await CleanMeasurer.size(of: URL(fileURLWithPath: worktree.path))) ?? 0
            stale.append(StaleWorktree(path: worktree.path, repository: repository, branch: worktree.branch, reason: reason, bytes: bytes))
        }
        return stale
    }

    /// Removes git's bookkeeping for worktrees whose folders are gone (after they were moved to the Trash).
    public func prune(_ repository: String) async {
        _ = await run(["-C", repository, "worktree", "prune"])
    }

    /// Why `head` counts as merged into `base`, or nil if it holds work `base` doesn't have.
    func mergeReason(head: String, base: String, repository: String) async -> String? {
        let name = base.replacingOccurrences(of: "origin/", with: "")
        if await succeeds(["-C", repository, "merge-base", "--is-ancestor", head, base]) {
            return "Merged into \(name)"
        }
        // Squash and rebase merges leave no ancestry; instead check that merging would change nothing.
        guard let merged = await run(["-C", repository, "merge-tree", "--write-tree", base, head])?
                .split(separator: "\n").first.map(String.init),
              let baseTree = await run(["-C", repository, "rev-parse", "\(base)^{tree}"])?
                .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return merged == baseTree ? "Squash-merged into \(name)" : nil
    }

    func defaultBranch(_ repository: String) async -> String? {
        if let remote = await run(["-C", repository, "symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD"])?
            .trimmingCharacters(in: .whitespacesAndNewlines), !remote.isEmpty {
            return remote
        }
        for candidate in ["origin/main", "origin/master", "main", "master"]
            where await succeeds(["-C", repository, "rev-parse", "--verify", "-q", candidate]) {
            return candidate
        }
        return nil
    }

    private func succeeds(_ arguments: [String]) async -> Bool {
        await execute(arguments).status == 0
    }

    /// Output of a successful git command, or nil on failure.
    private func run(_ arguments: [String]) async -> String? {
        let result = await execute(arguments)
        return result.status == 0 ? result.output : nil
    }

    private func execute(_ arguments: [String]) async -> (status: Int32, output: String) {
        let git = git
        return await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: git)
            process.arguments = arguments
            process.environment = ["GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C",
                                   "PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return (-1, "") }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
        }.value
    }
}
