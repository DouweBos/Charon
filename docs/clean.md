# Clean

The Clean tab sizes known places where space piles up and moves the selected ones to the Trash. Nothing is deleted outright: items go to the Trash, and emptying it goes through Finder, which asks first.

Categories marked **Rebuilt automatically** are selected by default; **Review first** ones are not.

| Category | Path | Safety |
|---|---|---|
| Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData/*` | Rebuilt |
| Device support files | `~/Library/Developer/Xcode/*DeviceSupport/*` | Rebuilt |
| SwiftUI previews | `~/Library/Developer/Xcode/UserData/Previews/*` | Rebuilt |
| Simulator caches | `~/Library/Developer/CoreSimulator/Caches/*` | Rebuilt |
| Xcode archives | `~/Library/Developer/Xcode/Archives/*` | Review (needed to symbolicate crashes) |
| Homebrew, SwiftPM, CocoaPods, npm, Yarn, Bun, pip, Go, Cargo, Gradle | their cache folders | Rebuilt |
| pnpm store | `~/Library/pnpm/store/*` | Review (projects hardlink into it) |
| App caches | `~/Library/Caches/*` minus the package caches above | Rebuilt |
| Logs | `~/Library/Logs/*` | Rebuilt |
| Mail attachments | `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/*` | Rebuilt |
| macOS installers | `/Applications/Install macOS*.app` | Rebuilt |
| Merged git worktrees | linked worktrees of repositories found in the last startup disk scan | Review |
| Trash | `~/.Trash` | Emptied via Finder |
| iPhone and iPad backups | `~/Library/Application Support/MobileSync/Backup/*` | Review |

The catalog lives in `CleanCatalog` (CharonKit). Sizes come from one scan per root; items in use or protected are skipped and reported.

Each row shows where the category lives. Right-click a row, or an item in its expanded list, to open that folder in the Map or Rings, reveal it in Finder, or copy its path.

## Merged git worktrees

For every repository in the last startup disk scan (a folder with a `.git` directory, outside `Library` and `node_modules`), Charon lists its linked worktrees and offers the ones that lose nothing when removed:

- no uncommitted or untracked changes (`git status --porcelain` is empty), not locked, not the main worktree;
- and either the worktree's commit is an ancestor of the default branch (`origin/HEAD`, else `main`/`master`), or merging it into the default branch would change nothing (`git merge-tree`), which catches squash and rebase merges.

Git runs with `GIT_OPTIONAL_LOCKS=0` so checking never rewrites an index. Cleaning moves the worktree folders to the Trash, then runs `git worktree prune` in their repositories. Branches are left alone.
