# Offload

Offloading moves a directory to the external drive (an external drive) and leaves a symlink in its place.

## Preflight

`OffloadPreflight` returns blockers (offload disabled) and warnings (user must acknowledge).

Blocked:
- System locations (`/System`, `/usr` except `/usr/local`, `/private`, `/Volumes`, parts of `/Library`, …) and SIP-protected items (`SF_RESTRICTED`)
- Container roots that must stay real directories (`/Applications`, `/Users`, `~`, `~/Library`, `~/Documents`, `~/Desktop`, …)
- `~/Library` areas macOS or sandboxed apps won't follow symlinks out of (Containers, Group Containers, Mobile Documents, CloudStorage, Keychains, Preferences, Mail, Messages, …)
- App and other bundles, anything inside one, and directories a running process executes from
- Symlinks, nested or repeat offloads, paths needing admin rights
- No drive, a drive without a volume UUID, the same volume, or less free space than size + 1 GB

Warned:
- Processes with open files or working directories inside (via libproc)
- Anything else in `~/Library`, `/opt/homebrew`, `/usr/local`
- Drives formatted exFAT/FAT (permissions and xattrs are lost)

## Crossing

Each step is written to the manifest before it runs:

| Phase | Step |
|---|---|
| `copying` | `copyfile` to `<Drive>/Charon/<id>/<name>` (data, xattrs, ACLs, modes, times, symlinks) |
| `verifying` | Compare structure, types, sizes, link targets and SHA-256 of every file; the copy is read with `F_NOCACHE` |
| `swapping` | Rename source to `.<name>.charon-<id>`, re-fingerprint it (catches late writes), create the symlink |
| `cleaning` | Delete the renamed source |
| `offloaded` | At rest |

Move back mirrors it (`returnCopying` → `returnVerifying` → `returnSwapping` → `returnCleaning`), copying into `.<name>.charon-return-<id>` on the home disk before replacing the symlink.

## Recovery

`OffloadEngine.reconcile()` runs at launch and whenever a drive mounts. Before the symlink exists, an offload is rolled back (original restored, partial copy removed); once the symlink exists it rolls forward. An aborted move back returns to `offloaded` unless the verified staging copy was already moved into place. If the drive is unplugged, cleanup waits until it's back. Tests in `OffloadRecoveryTests` crash at every step and unplug the drive mid-copy.

## Status

| Status | Meaning |
|---|---|
| Offloaded | Symlink points at a copy that exists |
| Disconnected | Drive not mounted; the symlink dangles |
| Drive moved | Drive mounted at a different path; Relink fixes the symlink |
| Broken | The symlink or the copy changed outside Charon; Forget drops the record |

Space freed is the total bytes of offloaded records. The manifest lives at `~/Library/Application Support/Charon/manifest.plist` and is mirrored to `<Drive>/Charon/manifest.plist`.
