# Security policy

## Reporting a vulnerability

If you believe you have found a security vulnerability in IconPing, please
**do not open a public GitHub issue**. Instead, email a private disclosure to:

**admin@opensubtitles.org**

Please include:

- A clear description of the issue and its potential impact
- Steps to reproduce, including the IconPing version (`Settings → About`),
  macOS version, and any relevant network setup
- (Optional) a proof-of-concept patch

You will receive an acknowledgement within **5 business days**. We aim to
release a fix within **30 days** for confirmed issues, and we will credit
the reporter in the release notes unless requested otherwise.

## Supported versions

Only the **latest tagged release** is actively patched. Older versions may
receive a security fix at the maintainer's discretion if the issue is severe
and the diff is small.

## Scope

IconPing's attack surface is intentionally minimal — no third-party network
endpoints, no telemetry, no privileged sockets. Areas that are in-scope for
security reports:

- The unprivileged ICMP datagram socket implementation
  (`Sources/IconPingCore/ICMPSocket.swift`, `ICMPPacket.swift`)
- The HTTPS speed-test code path (`SpeedTester.swift`)
- The GitHub-Releases-based update checker
  (`UpdateChecker.swift`) — verify URL/host construction can't be hijacked
- Anything that parses untrusted input from the network or from
  `UserDefaults`

Out of scope:

- Vulnerabilities that require physical access to an unlocked machine
- Issues that depend on bypassing macOS-level protections (e.g. SIP off)
- Denial of service that requires the attacker to already control the
  network path (since the app itself only pings what the user configures)
