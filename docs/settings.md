# Settings

All settings are in UserDefaults (`com.houwert.Charon`) and, unless noted, in the Settings window (⌘,).

| Key | Default | Where | Effect |
|---|---|---|---|
| `scan.largeFileThresholdMB` | 50 | Scanning | Files at least this big get their own treemap tile; smaller ones roll into "Files". Applies to the next scan. |
| `scan.rememberResults` | true | Scanning | Archive finished scans in `~/Library/Caches/com.houwert.Charon/Scans` and open on them next launch; Rescan refreshes. |
| `scan.measurePrivateSize` | false | Scanning | Also measure bytes not shared with APFS clones. Roughly doubles scan time; local Time Machine snapshots make it read low. |
| `treemap.depth` | 2 | Treemap | Nesting levels drawn at once (1–3). |
| `stats.visible` | true | Treemap | Show the live stat cards under Analyze. |
| `ferry.shoreFolder` | `Charon` | Ferry | Folder at the root of the Other Shore that holds ferried directories. Takes effect after relaunch. |
| `ferry.shoreVolumeID` | none | Ferry tab | The chosen Other Shore (volume UUID). Set from the Other Shore card, not the Settings window. |
