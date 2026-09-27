# Charon — Plan

Approved 2026-09-27. Scope: all milestones below. Offload verification: full SHA-256.

## Layout

```
app/Charon/
├── Charon.xcodeproj          # synchronized folders, no per-file pbxproj edits
├── Packages/CharonKit/       # engine: Foundation/CryptoKit/IOKit only, never SwiftUI/AppKit
│   ├── Sources/CharonKit/
│   │   ├── Scanner/          # getattrlistbulk walker, DiskTree arena
│   │   ├── Treemap/          # squarified + nested layout (pure)
│   │   ├── Offload/            # preflight, OffloadEngine (journaled copy/verify/swap), manifest, status
│   │   ├── Volumes/          # mounted volume catalog
│   │   ├── Stats/            # CPU/memory/disk/battery/network sampler
│   │   └── Support/          # byte formatting, posix helpers
│   └── Tests/CharonKitTests/
├── Charon/                   # SwiftUI app
│   ├── App/  Navigation/  ViewModels/  Views/{Root,Analyze,Offload,Stats,Settings}/
│   ├── DesignSystem/         # tokens + reusable components with #Previews
│   └── Utilities/
├── CharonTests/  CharonUITests/
```

## Scanner

- `getattrlistbulk(2)`: one syscall returns name, type, devid, flags, inode, link count, allocated size and (optional) APFS private size for a batch of entries.
- Worker threads (not Swift tasks; the syscalls block) pull directories from a shared LIFO queue. Each finished directory is attached to a lock-guarded arena and its bytes added up the ancestor chain, so a snapshot taken every 250 ms is a consistent partial tree and the treemap fills live.
- Boot disk: scan `/System/Volumes/Data` (where firmlinks point) and display it as `/`. Never cross devices (devid check), never follow symlinks.
- Hardlinks: files with `nlink > 1` counted once per (dev, inode).
- APFS clones: record allocated size and `ATTR_CMNEXT_PRIVATESIZE` (bytes actually freed). Treemap uses allocated; Offload shows reclaimable.
- Dataless (iCloud-evicted) files are never materialized (`IOPOL_MATERIALIZE_DATALESS_FILES_OFF`).
- Only directories and files above a threshold become nodes; smaller files roll into their directory's direct size.
- Space not visible to the scan (snapshots, purgeable, system volume) is shown as "System & other".

## Treemap

Squarified layout (Bruls et al.) as a pure function, nested N levels with header strips. Rendered in a SwiftUI `Canvas`; hit-testing on the flat tile list. Click drills in, breadcrumb/back goes out, sidebar and treemap share the navigation model.

## Offload

Preflight (blockers vs warnings):
- Block: system roots, SIP (`SF_RESTRICTED`), `.app` bundles and dirs containing a running executable, home and `~/Library` roots, iCloud/CloudStorage/Containers, already-symlinked or nested offloads, unwritable parent, not enough space, drive == source volume.
- Warn: processes with open files inside (libproc), non-APFS/HFS drive (exFAT loses permissions/xattrs), anything else in `~/Library`.

OffloadEngine (journaled; manifest saved before every transition):
1. `copying` → copy to `<Drive>/Charon/<id>/<name>` with `copyfile` (xattrs, ACLs, symlinks preserved).
2. `verifying` → walk both trees; compare structure, sizes, symlink targets and SHA-256 of every file (dest read with `F_NOCACHE`).
3. `swapping` → rename source to hidden sibling, quick metadata recheck, create symlink.
4. `cleaning` → delete hidden source → `offloaded`.

Move back mirrors it: copy back to hidden staging on the boot disk, verify, replace symlink with staging, delete drive copy. `reconcile()` on launch resumes or rolls back any record not at rest. Drives identified by volume UUID; remount under a new name is detected and the symlink relinked.

Status per record: Offloaded, Disconnected (drive unmounted), Drive moved (mounted elsewhere), Broken (symlink or target changed), In progress. Space freed = sum of reclaimed bytes.

Manifest: `~/Library/Application Support/Charon/manifest.plist`, mirrored best-effort to `<Drive>/Charon/manifest.plist`.

## Permissions

No sandbox (whole-disk reads, symlinks outside containers). Hardened runtime. Full Disk Access detected by probing a TCC-protected path; onboarding banner deep-links to System Settings. No privileged helper: root-owned paths are refused.

## Milestones

- M0 Scaffold, CLAUDE.md, docs, run config
- M1 Scanner + treemap + Analyze view on boot disk
- M2 Disk picker (external disks), rescan, reveal in Finder, context menus
- M3 OffloadKit with interruption / drive-loss tests
- M4 Offload UI: external drive picker, progress, Space freed, Disconnected, Move back, relink
- M5 Live stat cards
