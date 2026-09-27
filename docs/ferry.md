# Ferry

Ferrying moves a directory to the Other Shore (an external drive) and leaves a symlink in its place.

## Preflight

`FerryPreflight` returns blockers (ferry disabled) and warnings (user must acknowledge).

Blocked:
- System locations (`/System`, `/usr` except `/usr/local`, `/private`, `/Volumes`, parts of `/Library`, …) and SIP-protected items (`SF_RESTRICTED`)
- Container roots that must stay real directories (`/Applications`, `/Users`, `~`, `~/Library`, `~/Documents`, `~/Desktop`, …)
- `~/Library` areas macOS or sandboxed apps won't follow symlinks out of (Containers, Group Containers, Mobile Documents, CloudStorage, Keychains, Preferences, Mail, Messages, …)
- App and other bundles, anything inside one, and directories a running process executes from
- Symlinks, nested or repeat ferries, paths needing admin rights
- No shore, a shore without a volume UUID, the same volume, or less free space than size + 1 GB

Warned:
- Processes with open files or working directories inside (via libproc)
- Anything else in `~/Library`, `/opt/homebrew`, `/usr/local`
- Shores formatted exFAT/FAT (permissions and xattrs are lost)

## Crossing

Each step is written to the manifest before it runs:

| Phase | Step |
|---|---|
| `copying` | `copyfile` to `<Shore>/Charon/<id>/<name>` (data, xattrs, ACLs, modes, times, symlinks) |
| `verifying` | Compare structure, types, sizes, link targets and SHA-256 of every file; the copy is read with `F_NOCACHE` |
| `swapping` | Rename source to `.<name>.charon-<id>`, re-fingerprint it (catches late writes), create the symlink |
| `cleaning` | Delete the renamed source |
| `ferried` | At rest |

Bring home mirrors it (`returnCopying` → `returnVerifying` → `returnSwapping` → `returnCleaning`), copying into `.<name>.charon-return-<id>` on the home disk before replacing the symlink.

## Recovery

`Ferryman.reconcile()` runs at launch and whenever a drive mounts. Before the symlink exists, a ferry is rolled back (original restored, partial copy removed); once the symlink exists it rolls forward. An aborted bring-home returns to `ferried` unless the verified staging copy was already moved into place. If the shore is unplugged, cleanup waits until it's back. Tests in `FerryRecoveryTests` crash at every step and unplug the drive mid-copy.

## Status

| Status | Meaning |
|---|---|
| Ferried | Symlink points at a copy that exists |
| Stranded | Drive not mounted; the symlink dangles |
| Relocated | Drive mounted at a different path; Relink fixes the symlink |
| Broken | The symlink or the copy changed outside Charon; Forget drops the record |

Obols are the total bytes of ferried records. The manifest lives at `~/Library/Application Support/Charon/manifest.plist` and is mirrored to `<Shore>/Charon/manifest.plist`.
