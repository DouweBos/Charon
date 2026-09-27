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
| `Ferry/` | `FerryPreflight`, `Ferryman` (+ `Recovery`), `TreeCopier`, `TreeVerifier`, `ManifestStore`, `FerryStatus`, `ProcessInspector` |
| `Volumes/` | `VolumeCatalog`, `VolumeInfo`, `VolumeResolving` |
| `Stats/` | `SystemSampler` |
| `Support/` | `ByteSize` formatting, POSIX helpers |

### Scanning

- One `getattrlistbulk` call returns names, types, device, flags, inode, link count, allocated size (and optionally APFS private size) for a batch of entries.
- Worker threads pull directories from a LIFO queue. Each finished directory is attached to a mutex-guarded `DiskTree` and its bytes added up the ancestor chain, so snapshots (every 250 ms) are always consistent partial trees.
- The boot disk is scanned at `/System/Volumes/Data` and displayed as `/`. Other devices (mount points) are skipped, symlinks are not followed, dataless iCloud items are never materialized.
- Hardlinked files count once. Files under the large-file threshold roll into their folder's "Files".
- Finished scans are archived per volume by `ScanArchive` (JSON header plus raw column arrays) and reopened on launch.
- Used space the scan can't see (system volume, snapshots, purgeable) appears as "System & other" at the root.

## App (`app/Charon/Charon`)

| Folder | Contents |
|---|---|
| `App/` | `CharonApp`, `AppModel` (owns and wires everything), `CharonCommands` |
| `Navigation/` | `AppNavigator`: tab, volume, focus path, selection, history |
| `ViewModels/` | `AnalyzeViewModel`, `FerryViewModel`, `VolumesViewModel`, `StatsViewModel` |
| `Views/` | `Root/`, `Analyze/`, `Ferry/`, `Stats/`, `Settings/` |
| `DesignSystem/` | `Theme` tokens and reusable components, each with a `#Preview` |
| `Utilities/` | `AppSettings`, `SystemIntegration` (Finder, Full Disk Access), logging |

Colors live in `Assets.xcassets` with light and dark variants and are only referenced through `Theme`.

## Permissions

Not sandboxed: the scanner reads the whole disk and Ferry creates symlinks anywhere in the user's space. Hardened runtime is on. Full Disk Access is detected by probing TCC-protected files. There is no privileged helper, so root-owned paths can't be ferried.
