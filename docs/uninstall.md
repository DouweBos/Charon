# Uninstall

Lists third-party apps in `/Applications`, `/Applications/Utilities` and `~/Applications` with their size and when they were last opened (Spotlight's `kMDItemLastUsedDate`). Apple apps and Charon itself are not listed.

Selecting an app finds its leftovers in `~/Library`:

| Where | Matched by |
|---|---|
| Application Support, Caches, Logs | bundle ID, or app name (flagged "Might belong to another app", unchecked by default) |
| Containers, Application Scripts, Saved Application State, HTTPStorages, WebKit, Cookies | bundle ID |
| Preferences (`<bundle ID>.plist`, `ByHost/<bundle ID>.<hardware UUID>.plist`) | bundle ID |
| Group Containers, LaunchAgents | exactly the bundle ID (or `<TEAMID>.<bundle ID>`); longer IDs such as `<bundle ID>.helper` or `.beta` are listed but unchecked |

Move to Trash sends the app and the checked leftovers to the Trash. A running app must be quit first. Matching lives in `AppInventory` (CharonKit).

Apps with an empty or malformed bundle ID are skipped, so a bad ID can never expand to a whole Library folder.
