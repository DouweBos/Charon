# Contributing to Charon

Thanks for helping out. Bug reports, fixes and focused features are all welcome. For anything large, open an issue first so we can agree on the approach before you build it.

By taking part you agree to the [Code of Conduct](CODE_OF_CONDUCT.md). Report security issues privately as described in [SECURITY.md](SECURITY.md), never in a public issue.

## Requirements

- macOS 26.2 or later
- Xcode 26.2 or later (Swift 6.2)
- [SwiftLint](https://github.com/realm/SwiftLint) for linting (`brew install swiftlint`)

A free Apple ID is enough to build and run Charon. You don't need a paid Apple Developer account; that's only needed for Developer ID signing and notarization when distributing builds.

## Building from source

```sh
git clone https://github.com/DouweBos/Charon.git
cd Charon/app/Charon
open Charon.xcodeproj
```

Build and run the `Charon` scheme. From the command line:

```sh
cd app/Charon
xcodebuild -project Charon.xcodeproj -scheme Charon -derivedDataPath build -destination 'platform=macOS,arch=arm64' build
open build/Build/Products/Debug/Charon.app
```

### Signing with your own Apple team

The project is set up with the maintainer's team ID, which your Mac doesn't have a certificate for. Pick one of these:

- **Xcode**: select each target (Charon, CharonMonitor, CharonScanTool, CharonTests, CharonUITests), open **Signing & Capabilities** and choose your own team.
- **Command line, your team**: add `DEVELOPMENT_TEAM=<your team id>` to the `xcodebuild` command.
- **Command line, ad-hoc**: add `CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=` to sign ad-hoc without any account:

  ```sh
  xcodebuild -project Charon.xcodeproj -scheme Charon -derivedDataPath build -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
  ```

An ad-hoc signature changes with every build, so macOS may forget the Full Disk Access you granted and ask again. Signing with an Apple Development certificate (a free Apple ID works) keeps it stable.

**Don't commit a changed `DEVELOPMENT_TEAM`.** If Xcode rewrote it in `project.pbxproj`, leave that hunk out of your commit (`git add -p`).

### Permissions

Charon needs Full Disk Access for complete scans (System Settings → Privacy & Security → Full Disk Access). Scan as Administrator asks for your password through the standard macOS prompt each time; nothing privileged is installed.

## Tests and lint

```sh
cd app/Charon
(cd Packages/CharonKit && swift test)   # engine tests, headless
xcodebuild -project Charon.xcodeproj -scheme Charon -derivedDataPath build -destination 'platform=macOS,arch=arm64' test -only-testing:CharonTests
swiftlint lint --quiet
```

Engine tests create and move files in temporary directories only. Offload and Move back changes must come with tests that cover interruption and the drive disappearing mid-operation (see [docs/offload.md](docs/offload.md)).

If app tests stop with "test runner hung before establishing connection", macOS is most likely waiting on a Keychain prompt behind another window. Approve it and run the tests again.

## Code conventions

[CLAUDE.md](CLAUDE.md) describes the architecture and conventions in full. The short version:

- The engine (`Packages/CharonKit`) never imports SwiftUI or AppKit.
- ViewModels use `@Observable` and `@MainActor`. Filesystem work is `async throws`, never on the main thread, and long operations check `Task.isCancelled`.
- Colors come from named tokens defined for both light and dark, icons are SF Symbols, and reusable components live in `DesignSystem/` with a `#Preview`.
- Keep files under 500 lines and views under 300.
- Features use plain names (Offload, Move back, External drive). Charon is only the app name.
- A setting a user would reasonably want to change goes in Settings and in [docs/settings.md](docs/settings.md).

## Commits and pull requests

Each feature, fix or refactor is its own commit, with its tests and docs, so it stands alone and can be reverted.

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org): `type(scope): subject`, a single short sentence in lower case with no trailing period and no body.

- Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `chore`
- The scope is the area, not the path: `scanner`, `treemap`, `offload`, `ui`, `monitor`, … Reuse an existing scope where one fits (`git log --format=%s` shows them).

```
feat(offload): pick the external drive from the offload sheet
fix(analyze): keep the collector bar the same height in every phase
```

Before opening a pull request, make sure the app builds, the tests pass and SwiftLint is clean, and fill in the pull request template.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
