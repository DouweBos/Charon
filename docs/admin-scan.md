# Scan as Administrator

A normal scan runs as you. Full Disk Access lifts macOS's privacy protection, but folders owned by root or other users (`/private/var/db`, `.Spotlight-V100`, other accounts' homes) still can't be read, so their space lands in System & other.

**Scan as Administrator…** (the ••• menu, or the restricted-folders banner) runs `charon-scan`, a read-only scanner bundled in `Charon.app/Contents/MacOS`, once as root:

1. Charon checks that `charon-scan` is signed by the same team as the running app, so a replaced binary is never run as root.
2. It creates a private output folder in `~/Library/Caches/com.houwert.Charon/AdminScans/`.
3. It asks macOS for your administrator password (`do shell script … with administrator privileges`).
4. The tool scans, writing progress and the finished scan archive into that folder. It refuses output folders that are symlinks, aren't owned by you, or are writable by others, and creates files with `O_NOFOLLOW`. It stops when Charon drops a `cancel` file there.
5. Charon loads the archive like any other scan; the output folder is deleted.

Nothing privileged is installed or keeps running. Everything Charon changes on disk (Trash, offloads, cleaning) still happens as you, so root-owned items stay look-only. System Integrity Protection still applies to root.

Dismissing the password prompt restores the previous scan.
