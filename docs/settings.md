# Settings

All settings are in UserDefaults (`com.houwert.Charon`) and, unless noted, in the Settings window (⌘,).

| Key | Default | Where | Effect |
|---|---|---|---|
| `scan.largeFileThresholdMB` | 50 | Scanning | Files at least this big get their own treemap tile; smaller ones roll into "Files". Applies to the next scan. |
| `scan.rememberResults` | true | Scanning | Archive finished scans in `~/Library/Caches/com.houwert.Charon/Scans` and open on them next launch; Rescan refreshes. |
| `scan.measurePrivateSize` | false | Scanning | Also measure bytes not shared with APFS clones. Roughly doubles scan time; local Time Machine snapshots make it read low. |
| `treemap.depth` | 2 | Treemap | Nesting levels drawn at once (1–3). |
| `stats.visible` | true | Treemap | Show the live stat cards under Analyze. |
| `offload.driveFolder` | `Charon` | Offload | Folder at the root of the external drive that holds offloaded directories. Takes effect after relaunch. |
| `offload.driveVolumeID` | none | Offload tab | The chosen external drive (volume UUID). Set from the external drive card, not the Settings window. |
| `scan.recentFolders` | empty | Disk menu | Up to 8 recently scanned folders, listed under Folders in the disk menu. |
