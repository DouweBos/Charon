# Charon

A native macOS disk analyzer built with SwiftUI. It shows where the space on any disk goes, and ferries heavy directories to an external drive (the Other Shore), leaving a symlink behind so everything keeps working.

## Features

- Live, concurrent scan of the boot disk or any external disk
- Nested, drillable treemap with a matching sidebar and back/forward history
- Collector: gather files and folders, review the total, move them to the Trash (protected locations refused)
- "System & other" breakdown: system volume, VM/Preboot/Recovery, purgeable, restricted
- Ferry: preflight safety checks, copy, SHA-256 verification of every file, then symlink swap
- Ferried directory tracking: Ferried, Stranded (drive unplugged), Relocated, Broken; Bring home and Relink
- Crash-safe journal: interrupted ferries finish or roll back on next launch
- Live CPU, memory, disk, battery and network cards

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
- [Ferry](docs/ferry.md)
- [Settings](docs/settings.md)
