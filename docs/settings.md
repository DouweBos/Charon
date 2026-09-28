# Settings

All settings are in UserDefaults (`com.houwert.Charon`) and, unless noted, in the Settings window (⌘,).

| Key | Default | Where | Effect |
|---|---|---|---|
| `scan.largeFileThresholdMB` | 50 | Scanning | Files at least this big get their own treemap tile; smaller ones roll into "Files". Applies to the next scan. |
| `scan.rememberResults` | true | Scanning | Archive finished scans in `~/Library/Caches/com.houwert.Charon/Scans` and open on them next launch; Rescan refreshes. |
| `scan.measurePrivateSize` | false | Scanning | Also measure bytes not shared with APFS clones. Roughly doubles scan time; local Time Machine snapshots make it read low. |
| `files.ageFilterDays` | 0 | Largest Files | Only list files not opened for this many days (0 = any). Uses Spotlight's last-opened date, falling back to last modified. |
| `treemap.depth` | 3 | Treemap | Nesting levels drawn at once (1–4). Levels where one folder holds 85% or more (like Users → your home) don't count, so the map looks past them. |
| `offload.driveFolder` | `Charon` | Offload | Folder at the root of the external drive that holds offloaded directories. Takes effect after relaunch. |
| `offload.driveVolumeID` | none | Offload tab | The chosen external drive (volume UUID). Set from the external drive card, not the Settings window. |
| `scan.excludedPaths` | empty | Skipped folders | Folders every scan skips (also via Skip in Future Scans in Analyze). Their space shows up in System & other. |
| `scan.recentFolders` | empty | Disk menu | Up to 8 recently scanned folders, listed under Folders in the disk menu. |
| `monitor.lowGigabytes` | 20 | Menu Bar Monitor | Warn when free space drops below this many GB… |
| `monitor.lowPercent` | 5 | Menu Bar Monitor | …or below this share of the disk, whichever is larger. |
| `monitor.criticalGigabytes` | 5 | Menu Bar Monitor | Second, more urgent warning below this. |
| `monitor.showFreeSpace` | true | Menu Bar Monitor | Show free space next to the menu bar icon. |
| `monitor.notifyDisconnected` | true | Menu Bar Monitor | Notify when a drive holding offloaded folders disconnects or comes back. |

The monitor itself is turned on with "Show the monitor in the menu bar at login", which registers `CharonMonitor.app` (embedded in `Charon.app/Contents/Library/LoginItems`) through `SMAppService`. It reads these keys from the `com.houwert.Charon` defaults domain.

