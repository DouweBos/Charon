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
| Trash | `~/.Trash` | Emptied via Finder |
| iPhone and iPad backups | `~/Library/Application Support/MobileSync/Backup/*` | Review |

The catalog lives in `CleanCatalog` (CharonKit). Sizes come from one scan per root; items in use or protected are skipped and reported.
