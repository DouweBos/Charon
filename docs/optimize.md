# Optimize

Lists launch agents and daemons from `~/Library/LaunchAgents`, `/Library/LaunchAgents` and `/Library/LaunchDaemons`, parsed by `LaunchItemInventory` (CharonKit).

Each item shows the owning app (from the program path), whether it's running (`launchctl list`), whether it starts at login or is kept alive, and **App missing** when its program no longer exists, which usually means it was left behind by an uninstalled app.

Only your own agents can be removed: Charon runs `launchctl bootout gui/<uid> <plist>` and moves the plist to the Trash. System agents and daemons are shown for reference; Login Items Settings… opens System Settings for items managed there.
