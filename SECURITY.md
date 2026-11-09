# Security policy

Charon reads your whole disk, can run a scan as root, and moves your files between drives, so security reports are taken seriously.

## Reporting a vulnerability

Please report vulnerabilities privately, never in a public issue or pull request:

- [Open a private security advisory](https://github.com/DouweBos/Charon/security/advisories/new) on GitHub, or
- email **douwe@douwebos.nl**.

Include what you found, how to reproduce it, the Charon and macOS versions, and the impact you expect. You'll get an acknowledgement within a few days, and updates as it's investigated and fixed. Once it's fixed, you're credited in the advisory unless you'd rather not be.

## Scope

Especially welcome are reports about:

- Scan as Administrator (`charon-scan`, the root-run scanner) and the files it writes
- Offload and Move back losing or exposing data, or escaping the refusal rules for system and protected paths
- Clean, Uninstall or the Collector removing something other than what was shown

## Supported versions

Fixes land on `main`; only the latest version is supported.
