# Charon

A native macOS disk analyzer built with SwiftUI. It shows where the space on any disk goes, and offloads heavy directories to an external drive (the external drive), leaving a symlink behind so everything keeps working.

## Features

- Live, concurrent scan of the boot disk, any external disk, or any folder (Scan Folder… or drag one in)
- Scan as Administrator: a one-off root scan (password prompt, no installed helper) that sizes folders owned by macOS and other users
- Scans are remembered, so relaunching opens on the last result
- Nested, drillable treemap with a matching sidebar and back/forward history
- Rings: a sunburst view showing six levels at once; click a ring to open it, the center to go up
- Clean: sizes Xcode, simulator, package-manager and app caches, logs and leftovers, and moves them to the Trash
- Uninstall: apps by size and last use, with their leftovers in ~/Library
- Optimize: background launch agents and daemons, flagging ones whose app is gone
- Duplicates: identical large files (size, sampled hash, full SHA-256), skipping APFS clones
- Collector: gather files and folders, review the total, move them to the Trash (protected locations refused)
- "System & other" breakdown: system volume, VM/Preboot/Recovery, purgeable, restricted
- Offload: preflight safety checks, copy, SHA-256 verification of every file, then symlink swap
- Offloaded directory tracking: Offloaded, Disconnected (drive unplugged), Drive moved, Broken; Move back and Relink
- Crash-safe journal: interrupted offloads finish or roll back on next launch
- Menu bar monitor (login item): free space at a glance, warnings when it runs low, and alerts when a drive with offloaded folders disconnects

## Keyboard

| Key | Action |
|---|---|
| ↑ ↓ | Move the selection |
| → or Return | Open the selected folder |
| ← or ⌘↑ | Enclosing folder |
| Space | Quick Look |
| Delete | Add to Collector |
| ⌘[ ⌘] | Back, Forward |
| ⌘R | Rescan |
| ⌘1–⌘5 | Tabs |

## Requirements

- macOS 26.2+
- Xcode 27+
- Full Disk Access for complete scans (System Settings → Privacy & Security)

## Building

Open `app/Charon/Charon.xcodeproj` and build the `Charon` scheme, or:

```sh
cd app/Charon
xcodebuild -project Charon.xcodeproj -scheme Charon -derivedDataPath build -destination 'platform=macOS,arch=arm64' build
open build/Build/Products/Debug/Charon.app
```

Engine tests run headlessly: `cd app/Charon/Packages/CharonKit && swift test`.

## Docs

- [Architecture](docs/architecture.md)
- [Offload](docs/offload.md)
- [Scan as Administrator](docs/admin-scan.md)
- [Clean](docs/clean.md)
- [Uninstall](docs/uninstall.md)
- [Optimize](docs/optimize.md)
- [Settings](docs/settings.md)
