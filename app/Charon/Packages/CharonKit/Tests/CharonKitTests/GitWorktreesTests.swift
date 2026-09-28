// GitWorktreesTests.swift
// CharonKitTests

import Foundation
import Testing
@testable import CharonKit

struct GitWorktreesTests {
    @Test func parsesPorcelainListing() {
        let output = """
        worktree /repo
        HEAD 1111
        branch refs/heads/main

        worktree /repo-wt/feature
        HEAD 2222
        branch refs/heads/feature/login

        worktree /repo-wt/detached
        HEAD 3333
        detached

        worktree /repo-wt/kept
        HEAD 4444
        branch refs/heads/kept
        locked in use

        worktree /repo-wt/gone
        HEAD 5555
        prunable gitdir file points to non-existent location

        """
        let worktrees = GitWorktreeParser.parse(output)
        #expect(worktrees.count == 5)
        #expect(worktrees[0].isMain && worktrees[0].branch == "main")
        #expect(worktrees[1].branch == "feature/login" && !worktrees[1].isMain)
        #expect(worktrees[2].branch == nil && worktrees[2].head == "3333")
        #expect(worktrees[3].isLocked)
        #expect(worktrees[4].isPrunable)
    }

    @Test func findsRepositoriesInAScan() {
        var tree = DiskTree(rootPath: "/data", displayRootPath: "/")
        let work = tree.addNode(name: "Work", parent: DiskTree.root, kind: .directory)
        let app = tree.addNode(name: "app", parent: work, kind: .directory)
        _ = tree.addNode(name: ".git", parent: app, kind: .directory)
        let modules = tree.addNode(name: "node_modules", parent: app, kind: .directory)
        let dependency = tree.addNode(name: "dep", parent: modules, kind: .directory)
        _ = tree.addNode(name: ".git", parent: dependency, kind: .directory)
        #expect(GitWorktreeFinder.repositories(in: tree) == ["/data/Work/app"])
    }
}
