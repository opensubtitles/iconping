# IconPing

A tiny, native macOS menu-bar app that shows, at a glance, whether your internet connection is working — a colored status light (green / amber / red) that lives in your menu bar.

Modern spiritual successor to antirez's classic [`iconping`](https://github.com/antirez/iconping), rebuilt in Swift/SwiftUI for current macOS, with a real settings UI, a debug dashboard, configurable thresholds for flaky links, and full localization in **English, Italian, Spanish, Slovak, French**.

Designed for two users at once:

- **Non-technical users** — one thing: a light that turns red when the internet is down. Zero configuration.
- **Technical users** — open the dashboard and see latency, jitter, packet loss, history, and the active network path.

The motivating environment is an unreliable, high-latency, intermittently-dropping link (e.g. **Starlink on a boat**). IconPing distinguishes brief satellite-handoff blips from real outages and won't spam false "down" alerts.

## Features

- Menu-bar light: **green (OK) / amber (slow) / red (down)**, with distinct **shapes** in addition to color (colorblind-safe).
- Continuous low-overhead ICMP ping (IPv4 + IPv6), in-house engine, no root, no raw sockets.
- Dashboard window with live latency chart (Swift Charts), full stats grid, network path, event log, CSV export.
- Tabbed Settings: target, IP version, interval, timeout, payload size, latency-warn, debounce, presets (Satellite/Starlink, LAN/wired), appearance, notifications, language.
- "Simple mode" toggle collapses to just green/red.
- Localized in 5 languages.
- macOS 13 Ventura → latest. Universal binary (arm64 + x86_64).
- Open source, MIT.

## Install

### Download the DMG

Grab the latest `IconPing-x.y.z.dmg` from [Releases](https://github.com/opensubtitles/iconping/releases), open it, and drag IconPing to Applications.

> v1 ships ad-hoc signed (no paid Apple Developer ID yet). On first launch macOS will say "IconPing can't be opened because it is from an unidentified developer." Right-click the app in Applications → **Open** → **Open** in the dialog. After that it launches normally.
>
> Developer ID signing + notarization will land in a later release.

### Build from source

Requires only macOS **Command Line Tools** (Xcode optional).

```bash
git clone https://github.com/opensubtitles/iconping.git
cd iconping
./Scripts/build.sh
open build/IconPing.app
```

The build script compiles via Swift Package Manager, assembles a proper `.app` bundle, generates the procedural app icon, and ad-hoc signs the result. Add `--dmg` to also produce a DMG.

## Configuration

Defaults work out of the box (target `1.1.1.1`, 1 s interval, 2 s timeout, 2-sample debounce). Open **Settings…** from the menu to tune:

- **General:** target host (hostname or IP), IP version (auto/v4/v6), interval, timeout, payload size, **Presets** (Satellite / LAN / Default).
- **Thresholds:** latency-warn ms, failure debounce, recovery debounce, rolling-window size, Simple-mode toggle.
- **Appearance:** icon style, show latency text in menu bar, flash on change.
- **Notifications:** down/recovery, throttle interval, sound.
- **Startup:** Open at login (SMAppService).
- **Language:** System default or override (en/it/es/sk/fr).

### Presets

| Preset | Interval | Timeout | Failure debounce | Latency warn |
|---|---|---|---|---|
| Default | 1.0 s | 2000 ms | 2 | 300 ms |
| Satellite / Starlink | 1.0 s | 5000 ms | 3 | 600 ms |
| LAN / wired | 1.0 s | 1000 ms | 2 | 80 ms |

## Architecture

MVVM with a Swift-concurrency core:

```
Sources/
├── IconPingCore/      Pure engine: ICMP, state machine, stats, prefs
│   ├── ICMPPacket.swift
│   ├── ICMPSocket.swift
│   ├── PingEngine.swift          (actor)
│   ├── StateMachine.swift
│   ├── StatsAggregator.swift
│   ├── NetworkPathMonitor.swift
│   ├── Preferences.swift
│   └── Models.swift
└── IconPingApp/       UI shell
    ├── IconPingApp.swift          (@main)
    ├── MenuBarController.swift    (NSStatusItem)
    ├── DashboardView.swift
    ├── SettingsView.swift
    └── Resources/
        ├── en.lproj/Localizable.strings
        ├── it.lproj/Localizable.strings
        ├── es.lproj/Localizable.strings
        ├── sk.lproj/Localizable.strings
        └── fr.lproj/Localizable.strings
```

### Connectivity engine

Unprivileged datagram ICMP sockets (`SOCK_DGRAM` + `IPPROTO_ICMP`/`IPPROTO_ICMPV6`) — no root, no raw sockets, sandbox-compatible. Replies are matched by **sequence number** (the kernel rewrites the ICMP identifier for `SOCK_DGRAM`, see `ICMPSocket.swift` comments).

The state machine debounces with hysteresis: transition into `down` requires N consecutive failures, transition back to `up` requires M consecutive successes. The Satellite preset bumps both — designed for Starlink-on-a-boat reliability.

## Roadmap

Planned, not in v1:

- HTTP / TCP / DNS probes (architected; `Probe` protocol slot is wired in)
- Multiple targets / profiles
- Latency graph in the menu-bar dropdown, history persistence
- Mac App Store distribution (sandboxed)
- Developer ID signing + notarized release path
- Shortcuts / AppleScript support, Notification Center widget

## Localization

Strings live in `Sources/IconPingApp/Resources/<lang>.lproj/Localizable.strings`. Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). The Slovak and Italian translations were seeded for correctness (the maintainer is a native Slovak speaker and will notice errors) but native-speaker review on every language is appreciated.

## Credits

Inspired by Salvatore Sanfilippo (antirez)'s original [`iconping`](https://github.com/antirez/iconping) (BSD-3-Clause). Concept and the green/red dot lineage belong to him; this is a from-scratch Swift re-implementation under MIT.

## License

[MIT](LICENSE). Copyright © 2026 OpenSubtitles.
