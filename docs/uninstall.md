# Uninstall

Lists third-party apps in `/Applications`, `/Applications/Utilities` and `~/Applications` with their size and when they were last opened (Spotlight's `kMDItemLastUsedDate`). Apple apps and Charon itself are not listed.

Selecting an app finds its leftovers in `~/Library`:

| Where | Matched by |
|---|---|
| Application Support, Caches, Logs | bundle ID, or app name (flagged "Matched by name", unchecked by default) |
| Containers, Application Scripts, Saved Application State, HTTPStorages, WebKit, Cookies | bundle ID |
| Preferences (`<bundle ID>.plist`, `ByHost/*<bundle ID>*`) | bundle ID |
| Group Containers, LaunchAgents | folder or file name containing the bundle ID |

Move to Trash sends the app and the checked leftovers to the Trash. A running app must be quit first. Matching lives in `AppInventory` (CharonKit).
