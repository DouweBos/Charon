# Architecture

```
Filesystem ─→ CharonKit (engine, no UI imports) ─→ ViewModels (@MainActor @Observable) ─→ Views (SwiftUI)
                                                        ↑
                                              AppNavigator (single owner of navigation)
```

## CharonKit (`app/Charon/Packages/CharonKit`)

| Folder | Contents |
|---|---|
| `Scanner/` | `DiskScanner` (worker threads + `WorkQueue`), `BulkDirectoryReader` (`getattrlistbulk`), `DiskTree` (struct-of-arrays snapshot with `graft`/`detach`/CSV export), `ScanArchive`, `ScanComparison` |
| `Treemap/` | `SquarifiedLayout` (pure), `TreemapLayout` (nested tiles, hit-testing, shared level entries), `SunburstLayout` (rings) |
| `Offload/` | `OffloadPreflight`, `OffloadEngine` (+ `Recovery`), `TreeCopier`, `TreeVerifier`, `ManifestStore`, `OffloadStatus`, `ProcessInspector` |
| `Volumes/` | `VolumeCatalog`, `VolumeInfo`, `VolumeResolving`, `APFSInspector` (hidden space from `diskutil apfs list` and `tmutil`) |
| `Cleanup/` | `TrashPolicy` (what may be trashed), `CollectorSet`, `FileDeleter` (file-by-file deletion with progress), `CleanCatalog`, `CleanResolver`, `CleanMeasurer`, `AppInventory`, `DuplicateFinder` |
| `Startup/` | `LaunchItemInventory` |
| `Monitor/` | `LowSpacePolicy`, `MonitorSettings` (shared with the menu bar monitor) |
| `Support/` | `ByteSize` formatting, POSIX helpers |

### Scanning

- One `getattrlistbulk` call returns names, types, device, flags, inode, link count, allocated size (and optionally APFS private size) for a batch of entries.
- Worker threads pull directories from a LIFO queue. Each finished directory is attached to a mutex-guarded `DiskTree` and its bytes added up the ancestor chain, so snapshots (every 250 ms) are always consistent partial trees.
- The boot disk is scanned at `/System/Volumes/Data` and displayed as `/`. Other devices (mount points) are skipped, symlinks are not followed, dataless iCloud items are never materialized.
- Hardlinked files count once. Files under the large-file threshold roll into their folder's "Files".
- Finished scans are archived per volume by `ScanArchive` (JSON header plus raw column arrays) and reopened on launch.
- Used space the scan can't see appears as "System & other" at the root. Clicking it splits it into the system volume, support volumes (VM, Preboot, Recovery), purgeable space and restricted or snapshot-held data.

## App (`app/Charon/Charon`)

| Folder | Contents |
|---|---|
| `App/` | `CharonApp`, `AppModel` (owns and wires everything), `CharonCommands` |
| `Navigation/` | `AppNavigator`: tab, volume, focus path, selection, history |
| `ViewModels/` | One per area: Analyze, Offload, Volumes, HiddenSpace, Collector, Clean, Uninstall, Optimize, Duplicates; `LevelEntries`, `ScanTarget` |
| `Views/` | `Root/`, `Analyze/`, `Offload/`, `Clean/`, `Uninstall/`, `Optimize/`, `Settings/` |
| `DesignSystem/` | `Theme` tokens and reusable components, each with a `#Preview` |
| `Utilities/` | `AppSettings`, `SystemIntegration` (Finder, Full Disk Access), logging |

Colors live in `Assets.xcassets` with light and dark variants and are only referenced through `Theme`.

## Menu bar monitor (`app/Charon/CharonMonitor`)

A separate `LSUIElement` app embedded as a login item so it stays small (the main app can hold a multi-million-node scan). It polls free space every minute and on mount/unmount, uses `LowSpacePolicy` (with hysteresis) to decide when to notify, and reads the offload manifest to report disconnected drives. Settings are shared through the `dev.houwert.charon` defaults domain (`MonitorSettings`).

## Permissions

Not sandboxed: the scanner reads the whole disk and Offload creates symlinks anywhere in the user's space. Hardened runtime is on. Full Disk Access is detected by probing TCC-protected files. There is no privileged helper, so root-owned paths can't be offloaded.

## Changes since the last scan

Each archive save keeps the one it replaces as `<target>.previous.charonscan`. `ScanComparison` matches the two trees by display path; `topGrowth` attributes growth to the deepest folders that grew by at least 100 MB, listing a parent with its remainder when growth is spread across many small children. The Changes view in Analyze lists them, and the treemap caption shows each folder's change.
