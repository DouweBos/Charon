## What

<!-- What this changes, and why. Link the issue it closes, if any. -->

## How to test

<!-- Steps a reviewer can follow to see it working. -->

## Checklist

- [ ] Builds, tests pass (`swift test` in `Packages/CharonKit`, `xcodebuild test -only-testing:CharonTests`) and `swiftlint lint` is clean
- [ ] Commits follow Conventional Commits (`type(scope): subject`), one change per commit
- [ ] New or changed settings are in Settings and `docs/settings.md`; `docs/` matches the change
- [ ] Offload or Move back changes include tests for interruption and the drive disappearing mid-operation
- [ ] UI uses design-system color tokens and SF Symbols, and works in light and dark
- [ ] `DEVELOPMENT_TEAM` in `project.pbxproj` is unchanged
