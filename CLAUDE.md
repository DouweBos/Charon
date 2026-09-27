# Charon

macOS disk analyzer built with SwiftUI. Scans the boot disk or any external disk and shows where the space goes, then offloads heavy directories to an external drive, leaving a symlink behind.

## Vocabulary

Charon is the app name only. Features use plain names, never mythology:

- **Offload**: move a directory to an external drive and replace it with a symlink (UI: "Move to External Drive")
- **External drive**: the destination drive
- **Space freed**: bytes that now live on external drives
- **Disconnected**: an offloaded directory whose drive is unmounted (dangling symlink)
- **Move back**: restore an offloaded directory to its original location

## Development guidelines

- This is not a production app. Never plan or implement data migrations; just refactor directly.
- Prefer functions on ViewModels over writing to their properties directly. This makes adding analytics easier later.
- ViewModels use `@Observable` and `@MainActor`. No `ObservableObject`/`@Published`, no `DispatchQueue.main.async`.
- `async throws` for anything touching the filesystem. Never block the main thread; long operations check `Task.isCancelled`.

## Architecture

- **Engine vs UI**: scanning, treemap layout, and offload/restore logic live in a local Swift package that never imports SwiftUI or AppKit. That keeps the engine unit-testable headlessly and keeps views thin.
- **Navigation state has one owner.** The selected disk and drill-down path live in a single navigation model. Views read it and never mirror it into their own `@State`. A tab, drill-down, or selection that changes what a panel shows goes through that model, so back/forward works for free.

## Layout

```
app/Charon/
├── Charon.xcodeproj            # synchronized folders: new files under Charon/ are picked up automatically
├── Packages/CharonKit/         # engine package: Scanner/, Treemap/, Offload/, Cleanup/, Volumes/, Stats/, Support/
├── Charon/                     # App/, Navigation/, ViewModels/, Views/, DesignSystem/, Utilities/
├── CharonTests/  CharonUITests/
docs/                           # architecture.md, offload.md, settings.md
plan/                           # plans
```

- `AppNavigator` is the navigation model; `AppModel` owns it and every ViewModel and wires them together.
- The app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; the engine package is Swift 6 with no default isolation.

## Build and test

```sh
cd app/Charon
xcodebuild -project Charon.xcodeproj -scheme Charon -derivedDataPath build -destination 'platform=macOS,arch=arm64' build
xcodebuild -project Charon.xcodeproj -scheme Charon -derivedDataPath build -destination 'platform=macOS,arch=arm64' test -only-testing:CharonTests
(cd Packages/CharonKit && swift test)   # engine tests, headless
swiftlint lint --quiet                  # from app/Charon
```

Agents verify by compiling only (`build`, `swift build --build-tests`, lint). Never launch the app or run tests that touch the filesystem on the development Mac; the user runs them.

## Offload safety

Offloading moves user data. These rules are non-negotiable:

1. Copy, verify, then swap in the symlink. Never delete the source before the copy is verified.
2. Every step is recoverable: an interrupted offload leaves either the original or a verified copy, never neither.
3. Refuse system paths, SIP-protected locations, and anything inside a running app bundle.
4. Every offload is recorded in the manifest, which is the source of truth for disconnected detection and Move back.
5. Offload/restore logic ships with tests that cover interruption and the drive disappearing mid-operation.

## Conventions

**File size:** target <500 lines and split responsibilities when a file approaches that. Views <300 lines; extract subviews and move pure logic into the engine.

**Design system:**

1. All colors come from named tokens (asset catalog or a `Theme` type) that are defined for both dark and light. No `Color(red:…)`, hex literals, or inline opacity math in views.
2. Icons are SF Symbols only. No bundled icon fonts or third-party icon sets.
3. Reusable components live in one `DesignSystem/` folder, each with a `#Preview` covering its meaningful states. Check there before building a one-off.
4. No emoji in the UI.

**Configurability:** when adding a feature, ask whether the user would reasonably want to customize it. If so, make it a setting, surface it in Settings, and document it in `docs/settings.md`.

**Plan files:** write to `plan/`, never `docs/`. `docs/` describes the app as it stands.

**Commit when a thing is done.** Every feature, fix, or refactor gets its own commit as soon as it works, with its tests and docs included, so each commit stands alone and is revertable. Commit directly to `main`. Committing is not pushing: push only when asked.

**Commit messages:** Conventional Commits, `type(scope): subject`. One short single-sentence subject, lower case, no trailing period. No body paragraphs, no bullet lists, and no `Co-Authored-By` or any AI attribution.

- Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `chore`.
- The scope is the area, not the path (e.g. `scanner`, `treemap`, `offload`, `ui`). Reuse an existing scope before inventing another.

**Comments:** explain why, not what, in 1–2 lines. Describe the code as it stands, not its history.
