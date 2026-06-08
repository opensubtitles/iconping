# Contributing to IconPing

Thanks for your interest! IconPing is a small, focused utility — contributions should match that ethos.

## Build & run

```bash
./Scripts/build.sh
open build/IconPing.app
```

Or via SwiftPM only (without bundling):

```bash
swift build
swift run IconPing    # will work but won't bundle resources/icon properly — use build.sh for the real app
```

## Run tests

```bash
swift test
```

## Style

- Swift 5.9+ with strict concurrency. SwiftUI for views, `NSStatusItem` for the menu-bar item.
- No third-party runtime deps unless overwhelmingly justified.
- Code follows the existing layout — `IconPingCore` for pure logic (no AppKit/SwiftUI), `IconPingApp` for the UI shell.
- `swift-format` / `swiftlint` configs are not enforced yet; match surrounding style.

## Translations

Strings live in:

```
Sources/IconPingApp/Resources/<lang>.lproj/Localizable.strings
```

To add or improve a translation:

1. Open the appropriate `Localizable.strings` file.
2. Keep the keys identical to `en.lproj/Localizable.strings` — only the right-hand side changes.
3. Preserve format specifiers (`%@`, `%d`, `%.0f`) exactly.
4. Don't translate technical IPs, hostnames, or the product name `IconPing`.
5. Submit a PR. Native-speaker review is ideal.

To add a brand new language (e.g. Portuguese):

1. Create `Sources/IconPingApp/Resources/pt.lproj/Localizable.strings`.
2. Copy the English keys and translate.
3. Add the language code to the picker in `SettingsView.swift` (`General` tab → Language section).
4. Submit a PR.

## Reporting bugs

Open an issue with:

- macOS version + Mac model
- IconPing version
- Steps to reproduce
- Expected vs actual behavior
- (If a UI issue) screenshot/screen recording
- (If an engine issue) export the event log from Dashboard → **Export log…** and attach the CSV
