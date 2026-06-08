# Changelog

All notable changes to IconPing. Format follows [Keep a Changelog](https://keepachangelog.com/),
and the project aims for [SemVer](https://semver.org/).

## [1.0.12] — 2026-06-08

### Added
- **In-app update check.** New "Check for Updates…" menu item plus a silent
  on-launch check (5 s after start) that fetches the latest GitHub Release
  tag and alerts only when an update is genuinely available. Opens the
  Releases page in the user's browser. Translated in all 5 languages.
- **Translation review.** Ran every English string through DeepL Pro for
  IT/ES/SK/FR; the existing curated translations were kept where DeepL
  lost domain context (e.g. Slovak `notif.throttle = "Plyn"` would mean
  "gas pedal"). Report archived for future native-speaker passes.
- **Homebrew tap** — install via `brew tap opensubtitles/iconping && brew
  install --cask iconping`. Cask repo: `opensubtitles/homebrew-iconping`.
- **`SECURITY.md`** with private vulnerability reporting policy.
- This `CHANGELOG.md`.

### Changed
- **`LICENSE`** trimmed to plain MIT text so GitHub's license detector
  recognises it. antirez attribution moved to README "Credits" section.
- **Repository topics** set on GitHub for discoverability.

### Fixed
- LICENSE detection on the GitHub repo page (was "Other", now "MIT").

## [1.0.11] — 2026-06-08

### Added
- **Upload phase for the speed test.** Sequential download (Cloudflare
  `__down`) then upload (Cloudflare `__up`), each time-bounded at ~8 s.
  Final card shows both numbers side-by-side. Verdict still keys off the
  download number.

## [1.0.10] — 2026-06-08

### Changed
- **Speed test replaces Quick Test.** Streams from
  `https://speed.cloudflare.com/__down?bytes=90000000` (90 MB — Cloudflare
  rejects ≥ 100 MB), time-bounded at 8 s, with a live Mbps readout. Verdict
  brackets: ≥ 100 Excellent · ≥ 25 Good · ≥ 5 Fair · ≥ 1 Poor · < 1 Broken.

## [1.0.9] — 2026-06-08

### Added
- **Quick Test button** in the dashboard hero. 30-ping burst at 200 ms
  intervals; verdict card with avg/min/max/loss/jitter.
- **Git short hash in `About` and dashboard footer.** Stamped at build
  time via `git rev-parse --short HEAD` into `CFBundleVersion`.

### Fixed
- **Sleep/wake user-pause bug.** `didWake` no longer silently unpauses a
  session the user had manually paused before sleep.

## [1.0.8] — 2026-06-08

### Fixed
- **"Connection is slow" at 80 ms** even when the connection was fine.
  State machine now classifies slow/up off the *current* sample (with a
  3-sample debounce), not the 60-sample rolling average that could be
  dragged high by one cold-start ping for a full minute.
- **Chart looked broken with few samples.** X-axis now adapts to the
  number of samples (min 10 positions) so the line fills naturally from
  the left as data arrives. Y-axis clamped so the warn threshold is
  always on screen.
- **Menu bar icon invisible on first launch** because `UserDefaults`
  bools were read before `Preferences.shared` registered defaults.
- **`release.yml` now runs `swift test` before building the DMG.**

## [1.0.7] — 2026-06-08

### Added
- Strict hostname / IP-literal validation. Settings shows a red border +
  inline error on invalid input. Defensive clamping for every numeric
  preference on both read and write. "Reset all settings to defaults"
  button.

## [1.0.6] — 2026-06-08

### Added
- **Standard macOS top menus** (App / File / View / Window / Help) with
  About panel, Cmd+, settings, Cmd+D dashboard.
- **Version display in dashboard footer.**
- Diagnostic NSLog in the ping engine.

### Fixed
- **Engine: payload-based reply correlation.** Some macOS kernels rewrite
  the ICMP-header sequence with a global counter, causing every reply to
  be dropped on the floor and the state machine to flip to `.down`
  unconditionally. Replies are now correlated via a magic + session ID +
  app sequence embedded in the echo-request payload.

## [1.0.5] — 2026-06-08

### Added
- **Dock icon + menu-bar icon visible by default**, with toggles for each
  plus "Open dashboard on launch". Failsafe: if user hides both, dashboard
  pops up automatically so the app can never become invisible.

## [1.0.0] — 2026-06-08

### Added
- Initial release. ICMP-based menu-bar connectivity indicator with
  hero-status dashboard, color-coded stats grid, Swift Charts live graph,
  Cloudflare-anchored ping, debounce hysteresis for Starlink-style links,
  notifications, login item via `SMAppService`, 5 languages
  (en/it/es/sk/fr), tabbed Settings, MIT licensed.
