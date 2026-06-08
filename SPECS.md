# IconPing — Product & Engineering Specification

> **Purpose of this document.** This is a complete, implementation-ready specification for a modern macOS menu-bar connectivity indicator. It is written to be handed directly to an AI coding agent (e.g. Claude Code) or a human developer. A capable agent should be able to build, localize, test, and ship the app from this document with minimal further questions. Where a decision is intentionally left open, it is marked **[CONFIRM]**.

---

## 1. Summary

IconPing is a tiny, native macOS app that lives in the menu bar and shows, at a glance, whether your internet connection is working — via a colored status light (green / amber / red). It is a modern, maintained spiritual successor to antirez's classic `iconping`, rebuilt in Swift/SwiftUI for current macOS, with a real settings UI, a debug/dashboard window, configurable thresholds, and full localization in five languages.

It is designed for two kinds of user simultaneously:

- **Non-technical users** who want one thing: a light that turns red when the internet is down. Zero configuration required; sensible defaults out of the box.
- **Technical users** who want to open a window and see latency, jitter, packet loss, history, and the active network path.

The motivating environment is an unreliable, high-latency, intermittently-dropping link (e.g. **Starlink on a boat**): the app must distinguish brief satellite-handoff blips from genuine outages and must not spam false "down" alerts.

---

## 2. Goals and non-goals

### 2.1 Goals
- One-glance menu-bar status light: **green (OK) / amber (slow) / red (down)**.
- Continuous, low-overhead ICMP ping to a single, user-configurable target.
- A real **main window** ("dashboard") with live and historical connectivity data — not menu-bar-only.
- User-configurable **thresholds, interval, timeout, and debounce** so behavior can be tuned for flaky links.
- **Localization** in English, Italian, Spanish, Slovak, French.
- Modern, minimal, native macOS UI (SwiftUI). Light/dark mode, Dynamic Type, VoiceOver, colorblind-safe.
- **Open source** on GitHub, plus two shippable build paths: **Mac App Store (sandboxed)** and a **directly-distributed, notarized DMG**.
- Robust against network changes, sleep/wake, and IPv4/IPv6 environments.

### 2.2 Non-goals (this version)
- No HTTP/TCP/DNS/traceroute engine (ICMP only). *Architect for it, don't build it.*
- No monitoring of multiple targets at once (single target only). *Architect for it, don't build it.*
- No remote/cloud uptime service, no accounts, no telemetry, no analytics.
- No webhooks/alerting integrations (local notifications only).

These are explicitly deferred (see §15, Roadmap) and the architecture must not preclude them.

---

## 3. Naming & identity **[CONFIRM]**

- **Product name (working):** `IconPing`. The requester is fine reusing the original name. ⚠️ Note: antirez's repo is `antirez/iconping` (BSD-3). Reusing the exact name is legally fine but may cause user/search confusion. Options: keep `IconPing`, or differentiate (`IconPing 2`, `PingLight`, `Pulse`, `Beacon`). **Default assumed: `IconPing`.**
- **Bundle identifier:** reverse-DNS under a domain you control. **Default assumed:** `app.iconping.IconPing` (change freely).
- **GitHub repo:** `iconping` (or chosen name), public.
- **License:** **MIT** (permissive, simplest for contributors). Original was BSD-3-Clause; either is fine. **Default assumed: MIT.** Include the original copyright acknowledgement to antirez in the README/credits as a courtesy, since this is inspired by `iconping`.

---

## 4. Target platforms & toolchain

- **Minimum OS:** macOS **13.0 Ventura**. (Rationale: enables `MenuBarExtra`/modern SwiftUI, `SMAppService` login-item API, and String Catalogs without legacy shims.)
- **Tested up to:** latest public macOS (Sequoia 15.x / Tahoe 26.x at time of writing).
- **Architectures:** universal binary, `arm64` + `x86_64`.
- **Language:** Swift 5.9+ (Swift 6 language mode where practical; strict concurrency).
- **UI:** SwiftUI for windows/settings; AppKit `NSStatusItem` for the menu-bar item (more reliable than `MenuBarExtra` for custom-drawn status icons and click behavior).
- **Tooling:** Xcode 15+ (String Catalogs `.xcstrings`), SwiftLint + SwiftFormat, Swift Charts for graphs.
- **Dependencies:** prefer zero third-party runtime deps. The ICMP engine should be implemented in-house (see §6). If a dependency is used for ICMP, it must be MIT/BSD and vendored or pinned (candidate: `SwiftyPing`, MIT) — **but in-house is preferred** for auditability and sandbox/IPv6 control.

---

## 5. High-level architecture

Pattern: **MVVM** with a Swift-concurrency core.

```
App (SwiftUI @main)
├── Core
│   ├── PingEngine            (actor) — owns sockets, scheduling, sampling
│   ├── ICMPSocket            (IPv4 + IPv6 datagram ICMP)
│   ├── ICMPPacket            (encode/decode, checksum)
│   ├── Sample                (one ping result: seq, rtt, timestamp, status)
│   ├── ConnectivityState     (enum: unknown/up/slow/down)
│   ├── StateMachine          (debounce, thresholds → ConnectivityState)
│   ├── StatsAggregator       (rolling min/avg/max, jitter, loss%, uptime%)
│   └── NetworkPathMonitor    (NWPathMonitor wrapper: interface, IPs, gateway)
├── Features
│   ├── MenuBar               (NSStatusItem controller + popover/menu)
│   ├── Dashboard             (main window: live graph, stats, event log)
│   └── Settings              (SwiftUI Settings scene)
├── Services
│   ├── Preferences           (@AppStorage-backed settings store)
│   ├── NotificationService   (UNUserNotificationCenter)
│   └── LaunchAtLoginService  (SMAppService.mainApp)
└── Resources
    ├── Assets.xcassets       (status icons, app icon)
    └── Localizable.xcstrings  (en base + it/es/sk/fr)
```

**Data flow:** `PingEngine` (an `actor`) emits `Sample` values through an `AsyncStream`. A `@MainActor` view model consumes the stream, feeds `StateMachine` and `StatsAggregator`, and publishes `@Published` properties consumed by the menu-bar controller, dashboard, and settings. `NetworkPathMonitor` signals path changes that cause the engine to rebind sockets and reset transient stats.

---

## 6. Connectivity engine (ICMP)

### 6.1 Socket strategy
- Use **unprivileged datagram ICMP sockets** — no root, no setuid, sandbox-compatible:
  - IPv4: `socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)`
  - IPv6: `socket(AF_INET6, SOCK_DGRAM, IPPROTO_ICMPV6)`
- These work for normal users on Darwin and inside the App Sandbox **with the `com.apple.security.network.client` entitlement**. No raw sockets.
- **Identifier handling:** with `SOCK_DGRAM` ICMP the kernel rewrites the ICMP `identifier` to a kernel-assigned value tied to the socket's local port, and computes the checksum. Therefore: **do not match replies on your own identifier.** Match on **sequence number** (and validate payload echo). This is the well-known `SimplePing` behavior — follow it. Document this in code comments.
- Set socket non-blocking; integrate with the run loop / `DispatchSource` or use `recvfrom` on a dedicated `Task`.
- For IPv6, the kernel computes the ICMPv6 checksum; do not compute it manually.

### 6.2 Target resolution
- Target is a **hostname or IP** (default `1.1.1.1`). Resolve via `getaddrinfo`/`NWEndpoint` to A and/or AAAA records.
- **IP version preference** setting: `auto` (prefer whatever the active path supports; try IPv4 first, fall back to IPv6), `IPv4 only`, `IPv6 only`.
- Re-resolve on target change and on network-path change.
- Display the **resolved IP** in the dashboard so the user can see what's actually being pinged.

### 6.3 Sampling loop
- Send one ICMP echo request every **interval** (default 1.0 s; range 0.25 s – 60 s).
- Each request: monotonically increasing sequence number, embed a high-resolution send timestamp in the payload (and keep a local map seq→sendTime as the source of truth; never trust the echoed timestamp for security but use it as a cross-check).
- Payload size configurable (default 56 bytes data, matching `ping`'s default; range 0–1452).
- A request with no matching reply within **timeout** (default 2000 ms; **recommend 5000 ms preset for satellite**) counts as a **loss**.
- Compute **RTT** = receiveTime − sendTime (monotonic clock, e.g. `clock_gettime(CLOCK_MONOTONIC_RAW)` / `DispatchTime`).

### 6.4 Statistics (rolling window)
Maintain over a configurable rolling window (default last 60 samples *and* lifetime-since-reset):
- `rttLast`, `rttMin`, `rttAvg`, `rttMax`
- `jitter` = mean absolute deviation of consecutive RTTs (or RFC 3550 interarrival jitter — pick one, document it)
- `packetLoss%` over the window
- `uptime%` (fraction of time in `up`/`slow` vs `down`) since last reset
- counts: sent, received, lost

### 6.5 IPv4/IPv6 packet details
- Implement `ICMPPacket` encode/decode for both ECHO request/reply (type 8/0 for v4, 128/129 for v6).
- Provide the standard BSD 16-bit ones-complement checksum for any path that needs it (defensive; kernel handles datagram sockets).
- Unit-test encode/decode/checksum against known vectors.

---

## 7. State machine & thresholds

### 7.1 States
`unknown` (startup, before first result) → `up` / `slow` / `down`.

### 7.2 Classification (per evaluation tick)
- **down** if the last *N* consecutive samples were lost (N = `failureDebounce`, default **2**) **or** time since last successful reply > `timeout × failureDebounce`.
- **slow** if currently receiving replies but `rttAvg(window)` ≥ `latencyWarnMs` (default **300 ms**).
- **up** otherwise.

### 7.3 Debounce / hysteresis (critical for Starlink)
- Transition **into `down`** requires `failureDebounce` consecutive failures (default 2). This prevents single dropped handoff packets from flipping the light.
- Transition **out of `down`** requires `recoveryDebounce` consecutive successes (default 1).
- All debounce/threshold values are user-configurable in Settings, with a one-click **"Satellite / Starlink" preset** (timeout 5000 ms, interval 1 s, failureDebounce 3, latencyWarn 600 ms) and a **"LAN / wired" preset** (timeout 1000 ms, interval 1 s, failureDebounce 2, latencyWarn 80 ms).

### 7.4 Two-state mode
A settings toggle **"Simple mode (green/red only)"** collapses `slow`→`up` so non-technical users see only green or red. Default **off** (3-state).

---

## 8. User interface

### 8.1 Menu-bar item (`NSStatusItem`)
- A custom-drawn status icon reflecting state. **Do not rely on color alone** (colorblind users): use distinct *shapes/glyphs* per state in addition to color:
  - `up` → filled circle, green
  - `slow` → half-filled circle (or circle with a small clock/▲), amber
  - `down` → hollow circle with an `×` (or `slash.circle`), red
  - `unknown` → dotted/gray circle
- Use SF Symbols where possible (`circle.fill`, `circle.bottomhalf.filled`, `xmark.circle`, `circle.dotted`) tinted via template rendering so they adapt to menu-bar light/dark and "reduce transparency".
- **Tooltip:** localized current status + `rttLast` + `loss%` (e.g. "Connection OK · 42 ms · 0% loss").
- **Click behavior:**
  - Left-click → open a compact **popover** with: status line, latency, loss, jitter, a tiny sparkline, and buttons [Open Dashboard] [Settings].
  - Right-click (or click on the menu) → menu with: status summary (disabled item), **Open Dashboard**, **Settings…**, **Open at login** (checkmark toggle), **Pause/Resume monitoring**, **Quit IconPing**.
- Optional **"flash on state change"** (off by default, like the original's non-flicker option) and optional **"show latency text next to icon"** toggle.

### 8.2 Dashboard window (the "debug data" view)
A single, minimal, resizable window. Sections:
- **Header:** big colored status word ("Connection OK"), current RTT, target host + resolved IP, IP version in use.
- **Live latency chart** (Swift Charts): RTT over the last N samples; lost packets marked distinctly (e.g. red ticks at baseline). Amber/red threshold guide lines.
- **Stats grid:** min / avg / max RTT, jitter, packet loss %, uptime %, sent/received/lost counts, time since reset. [Reset stats] button.
- **Network path:** active interface name & type (Wi-Fi/Ethernet/etc. from `NWPathMonitor`), local IPv4/IPv6, gateway, DNS servers (read-only; informational). Copy-to-clipboard on each.
- **Event log:** timestamped state transitions and notable events (down at HH:MM:SS, recovered after Xs, network path changed, target changed). Scrollable, newest-first.
- **Controls:** Pause/Resume, change target inline, [Export log…] (CSV via `NSSavePanel`).

### 8.3 Settings (SwiftUI `Settings` scene, tabbed)
- **General:** target host; IP version (auto/v4/v6); interval; timeout; payload size; presets (Satellite, LAN, Default).
- **Thresholds:** latency-warn ms; failure debounce; recovery debounce; rolling-window size; Simple mode toggle.
- **Appearance:** icon style; show latency text in menu bar; flash on change; 3-state vs simple.
- **Notifications:** enable on down / on recovery; throttle interval; sound on/off.
- **Startup:** Open at login (SMAppService).
- **Language:** "System default" + explicit override (en/it/es/sk/fr) using the per-app language override (writes `AppleLanguages`); note macOS 13+ has native per-app language in System Settings too.
- **About:** version, GitHub link, license, credit to antirez's iconping.

### 8.4 Design language
- Minimal, lots of whitespace, SF Pro, native materials (`.regularMaterial` backgrounds). No skeuomorphism. Respect Increase Contrast / Reduce Motion / Reduce Transparency. The dashboard should feel like a focused single-purpose Apple utility, not a dashboard-with-everything.

---

## 9. Localization

- Use a **String Catalog** (`Localizable.xcstrings`), English as the development/base language, with full translations for **Italian (it), Spanish (es), Slovak (sk), French (fr)**.
- All user-facing strings localized, including tooltips, notifications, accessibility labels, menu items, and number/unit formatting (use `MeasurementFormatter`/locale-aware formatting; show ms with locale decimal separator).
- Pluralization where relevant via `.stringsdict`/catalog plural variations (e.g. "%d packets lost").
- Right-to-left not required (none of the five languages are RTL).

### 9.1 Core string table (seed translations — review by native speakers; Slovak/Italian provided with care)

| Key | English (base) | Italiano | Español | Slovenčina | Français |
|---|---|---|---|---|---|
| `status.ok` | Connection OK | Connessione OK | Conexión correcta | Pripojenie OK | Connexion OK |
| `status.slow` | Connection is slow | Connessione lenta | Conexión lenta | Pomalé pripojenie | Connexion lente |
| `status.down` | No connection | Nessuna connessione | Sin conexión | Žiadne pripojenie | Pas de connexion |
| `status.unknown` | Checking… | Controllo in corso… | Comprobando… | Kontrola… | Vérification… |
| `metric.latency` | Latency | Latenza | Latencia | Odozva | Latence |
| `metric.loss` | Packet loss | Perdita di pacchetti | Pérdida de paquetes | Strata paketov | Perte de paquets |
| `metric.jitter` | Jitter | Jitter | Fluctuación (jitter) | Kolísanie (jitter) | Gigue |
| `metric.uptime` | Uptime | Tempo di attività | Tiempo activo | Dostupnosť | Disponibilité |
| `metric.min` | Min | Min | Mín | Min | Min |
| `metric.avg` | Avg | Media | Media | Priemer | Moyenne |
| `metric.max` | Max | Max | Máx | Max | Max |
| `field.target` | Target host | Host di destinazione | Host de destino | Cieľový hostiteľ | Hôte cible |
| `field.interval` | Interval | Intervallo | Intervalo | Interval | Intervalle |
| `field.timeout` | Timeout | Timeout | Tiempo de espera | Časový limit | Délai d'expiration |
| `menu.dashboard` | Open Dashboard | Apri pannello | Abrir panel | Otvoriť prehľad | Ouvrir le tableau de bord |
| `menu.settings` | Settings… | Impostazioni… | Ajustes… | Nastavenia… | Réglages… |
| `menu.loginItem` | Open at login | Apri all'avvio | Abrir al iniciar sesión | Spustiť pri prihlásení | Ouvrir à la connexion |
| `menu.pause` | Pause monitoring | Sospendi monitoraggio | Pausar monitorización | Pozastaviť monitorovanie | Suspendre la surveillance |
| `menu.resume` | Resume monitoring | Riprendi monitoraggio | Reanudar monitorización | Pokračovať v monitorovaní | Reprendre la surveillance |
| `menu.quit` | Quit IconPing | Esci da IconPing | Salir de IconPing | Ukončiť IconPing | Quitter IconPing |
| `action.reset` | Reset stats | Azzera statistiche | Restablecer estadísticas | Vynulovať štatistiku | Réinitialiser les stats |
| `action.export` | Export log… | Esporta log… | Exportar registro… | Exportovať záznam… | Exporter le journal… |
| `notif.down.title` | Internet connection lost | Connessione a Internet persa | Conexión a Internet perdida | Pripojenie na internet sa stratilo | Connexion Internet perdue |
| `notif.up.title` | Internet connection restored | Connessione a Internet ripristinata | Conexión a Internet restablecida | Pripojenie na internet je obnovené | Connexion Internet rétablie |
| `preset.satellite` | Satellite / Starlink | Satellite / Starlink | Satélite / Starlink | Satelit / Starlink | Satellite / Starlink |
| `preset.lan` | LAN / wired | LAN / cablata | LAN / cableada | LAN / káblové | LAN / filaire |
| `a11y.status` | Connection status: %@ | Stato connessione: %@ | Estado de conexión: %@ | Stav pripojenia: %@ | État de la connexion : %@ |

> Translation note for the implementer: have a native speaker proof Slovak and Italian especially. The requester is a native Slovak speaker and will notice errors. "Odozva" (latency/response) and "Strata paketov" (packet loss) are the natural Slovak technical terms; keep "jitter" loanword with a gloss.

---

## 10. Persistence & state

- **Settings:** `@AppStorage` (UserDefaults). Keys namespaced (`engine.targetHost`, `engine.intervalMs`, `thresholds.latencyWarnMs`, `ui.simpleMode`, etc.). Provide a typed `Preferences` wrapper with defaults.
- **History:** in-memory ring buffer (default capacity 3600 samples ≈ 1 h at 1 s). Not persisted across launches (privacy + simplicity). Stats reset on relaunch and on user reset.
- **Export:** CSV (`timestamp,seq,rtt_ms,status`) via `NSSavePanel`; on sandbox, the panel grants the write scope automatically.

---

## 11. Notifications

- `UNUserNotificationCenter`; request authorization on first enable (not on launch).
- Fire on transition to `down` (after debounce) and optionally on recovery to `up`.
- **Throttle:** no more than one down-notification per `notifThrottle` (default 60 s) to avoid spam on a flapping link.
- Respect Focus / Do Not Disturb (system handles). Sound optional, default off.

---

## 12. Launch at login

- Use **`SMAppService.mainApp`** (macOS 13+). Toggle in menu and Settings; reflect actual registration status (`.status`). No legacy `LSSharedFileList` (deprecated/non-functional). No helper login-item target needed for the main-app registration approach.

---

## 13. Networking robustness & edge cases

The implementation must handle:
- **Network path changes** (Wi-Fi ↔ Starlink ↔ Ethernet): `NWPathMonitor` triggers socket rebind, re-resolve target, and a transient-stats reset (keep lifetime stats, mark an event-log entry).
- **Sleep/wake:** observe `NSWorkspace.willSleepNotification`/`didWakeNotification`; pause sending on sleep, resume + reset transient state on wake (avoid a giant fake "outage" spanning sleep).
- **No route / interface down:** classify as `down`, but log the cause distinctly when known (no route vs timeout).
- **DNS failure** when target is a hostname: surface as a distinct state/message ("Can't resolve host") rather than a generic outage; keep retrying resolution.
- **IPv6-only networks:** must work (hence dual-stack engine and `auto` preference).
- **Captive portals / "connected but no internet":** ICMP to a public IP is a decent proxy, but document the known limitation that some captive networks pass ICMP. (A future HTTP check — §15 — would disambiguate; out of scope now.)
- **Target unreachable vs internet down:** because we ping one public anchor (default `1.1.1.1`), a red light means "can't reach the anchor." Document that the user can change the target. (Multi-target disambiguation is future scope.)

---

## 14. Distribution, signing, CI/CD

Open source on GitHub with **two release artifacts** from one codebase:

### 14.1 Build configurations
- **Direct (notarized DMG):** Developer ID Application signing, **Hardened Runtime** on, notarized via `notarytool`, stapled, packaged as DMG (`create-dmg`). Sandbox optional but recommended on.
- **Mac App Store:** App Sandbox **on**, entitlement `com.apple.security.network.client` (verify ICMP datagram sockets function under sandbox — they do with this entitlement; include an integration check). App Store provisioning profile + distribution cert.
- Share one target; vary entitlements/signing per configuration (xcconfig files: `Direct.xcconfig`, `AppStore.xcconfig`).

### 14.2 Entitlements
- App Sandbox: `com.apple.security.app-sandbox = true` (App Store + recommended for Direct).
- `com.apple.security.network.client = true` (required for outbound ICMP).
- `com.apple.security.files.user-selected.read-write = true` (for CSV export panel).
- No incoming/server entitlement; no other capabilities.

### 14.3 GitHub Actions (CI)
- On PR/push: `macos-latest` runner → resolve deps → SwiftLint/SwiftFormat check → build → run unit tests.
- On tag `v*`: build Release (Direct config) → sign (Developer ID, secrets) → notarize (`notarytool`, secrets: API key) → staple → `create-dmg` → create GitHub Release and upload DMG + checksums.
- Optional separate workflow for App Store upload (`xcrun altool`/`notarytool` + `xcrun stapler`, or `fastlane deliver`) gated on a manual dispatch.
- Secrets: signing cert (base64 .p12), App Store Connect API key, keychain password — all via repo secrets, never committed.

### 14.4 Repo hygiene
- README (what it is, screenshots, install both ways, build instructions, credit to antirez), LICENSE (MIT), CONTRIBUTING, localization contribution guide, `.github/workflows`, Issue templates.

---

## 15. Roadmap / planned extension points (do not build now, do not preclude)

Architect cleanly so these are additive, not rewrites:
- **Pluggable probe protocol:** `Probe` protocol with `ICMPProbe` as the only implementation now; later `HTTPProbe`, `TCPConnectProbe`, `DNSProbe`. The engine/state machine should consume an abstract `ProbeResult`.
- **Multiple targets / profiles:** the data model should allow a `Monitor` to own a list of targets even if the UI exposes one. Menu-bar light shows aggregate or "primary."
- **Latency graph in the menu-bar dropdown**, history persistence, per-network presets, traceroute view, Shortcuts/AppleScript support, Notification Center widget.

---

## 16. Testing & acceptance

### 16.1 Unit tests
- ICMP checksum vectors; packet encode/decode (v4 + v6).
- RTT computation from monotonic clock.
- State machine: every transition incl. debounce (no flip on single loss; flip after N losses; recovery after M successes; slow classification at threshold boundaries).
- Stats: rolling min/avg/max, jitter, loss%, uptime% on synthetic sample streams.
- Preferences load/save/defaults; preset application.

### 16.2 Manual / integration QA
- Pull the Ethernet/Wi-Fi → red within `interval × failureDebounce + timeout`; restore → green within recovery debounce.
- Switch networks mid-run → no spurious outage, event logged, sockets rebind.
- Sleep 5 min, wake → no fake multi-minute outage.
- IPv6-only network → still functions (`auto`).
- Sandboxed (App Store config) build → ICMP works; CSV export works.
- All five languages render without truncation in menu, popover, settings, notifications.
- VoiceOver announces status; colorblind shapes distinguishable with color filters on.

### 16.3 Acceptance criteria (definition of done)
- [ ] Menu-bar light reflects up/slow/down with distinct color **and** shape.
- [ ] Default config (target `1.1.1.1`, 1 s, 2000 ms, debounce 2) works with zero setup.
- [ ] Dashboard shows live chart, full stats, network path, event log, export.
- [ ] Settings expose target, interval, timeout, thresholds, debounce, presets, appearance, notifications, login, language.
- [ ] Starlink preset visibly reduces false outages vs default on a flaky link.
- [ ] Five languages complete; numbers/units locale-formatted.
- [ ] Builds and runs on macOS 13 → latest, universal binary.
- [ ] Both artifacts produced: notarized DMG + App Store-ready archive, from CI.
- [ ] No root, no raw sockets, no telemetry. Sandboxed build fully functional.
- [ ] Open-source repo with README, license, CI, contribution/localization docs.

---

## 17. Open questions for the requester **[CONFIRM]**

1. **Name & bundle id:** keep `IconPing` + `app.iconping.IconPing`, or differentiate? (See §3.)
2. **License:** MIT (assumed) or BSD-3-Clause to mirror the original?
3. **Default target:** `1.1.1.1` (assumed) or `8.8.8.8` (what antirez used) or your own anchor (e.g. an OpenSubtitles host)?
4. **App Store actually wanted now**, or is the sandbox-clean/notarized-DMG path enough for v1 and App Store later? (Both are specced; this only affects whether you set up the paid App Store distribution cert/CI now.)
5. **Min OS 13.0** acceptable, or do you need to support older (12 Monterey) at the cost of some modern APIs?

---

*End of specification.*

