# Architecture

```
Filesystem ─→ CharonKit (engine, no UI imports) ─→ ViewModels (@MainActor @Observable) ─→ Views (SwiftUI)
                                                        ↑
                                              AppNavigator (single owner of navigation)
```

## CharonKit (`app/Charon/Packages/CharonKit`)

| Folder | Contents |
|---|---|
| `Scanner/` | `DiskScanner` (worker threads + `WorkQueue`), `BulkDirectoryReader` (`getattrlistbulk`), `DiskTree` (struct-of-arrays snapshot), `ScanArchive` |
| `Treemap/` | `SquarifiedLayout` (pure), `TreemapLayout` (nested tiles, hit-testing, shared level entries) |
| `Offload/` | `OffloadPreflight`, `OffloadEngine` (+ `Recovery`), `TreeCopier`, `TreeVerifier`, `ManifestStore`, `OffloadStatus`, `ProcessInspector` |
| `Volumes/` | `VolumeCatalog`, `VolumeInfo`, `VolumeResolving`, `APFSInspector` (hidden space from `diskutil apfs list` and `tmutil`) |
| `Cleanup/` | `TrashPolicy` (what may be trashed), `CollectorSet` |
| `Stats/` | `SystemSampler` |
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
| `ViewModels/` | `AnalyzeViewModel`, `OffloadViewModel`, `VolumesViewModel`, `StatsViewModel` |
| `Views/` | `Root/`, `Analyze/`, `Offload/`, `Stats/`, `Settings/` |
| `DesignSystem/` | `Theme` tokens and reusable components, each with a `#Preview` |
| `Utilities/` | `AppSettings`, `SystemIntegration` (Finder, Full Disk Access), logging |

Colors live in `Assets.xcassets` with light and dark variants and are only referenced through `Theme`.

## Permissions

Not sandboxed: the scanner reads the whole disk and Offload creates symlinks anywhere in the user's space. Hardened runtime is on. Full Disk Access is detected by probing TCC-protected files. There is no privileged helper, so root-owned paths can't be offloaded.
