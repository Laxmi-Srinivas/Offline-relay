# Final hackathon integration verification

Verified on macOS on 2026-10-04 from integration checkpoint `6b0f865`.
Scope: **Android ↔ Android; iPhone ↔ iPhone; website and installation guidance**.
Android ↔ iPhone is excluded. No networking implementation was rewritten.

## Preserved applications

- Android: `apps/offline_relay` and `packages/relay_transport` are unchanged from
  `cf59a02`. Service-UUID filtering and Android service-data metadata discover
  helpers. DATA write/notify and ACK read/write carry bounded 256-byte envelopes.
  Explicit acceptance precedes X25519/HKDF/AES-GCM setup and encrypted chat,
  confirmation and End Chat. The exchange does not authenticate peer identity.
- iOS: `apps/offline_relay_ios` depends only on `packages/relay_transport_ios`.
  Compared with `ios-mvp` source `4cf4865`, all native Swift, the transport package
  and application behavior are preserved; existing integration changes were
  display branding and the relocated dependency. The lockfile now agrees with
  that dependency. No iOS protocol or native behavior changed during verification.
- iOS uses CoreBluetooth service advertising, short local names and readable
  PROFILE metadata, per-link central sessions, DATA/ACK framing, request/accept/
  reject/chat envelopes, first-accept winner selection and losing-link cleanup.
  The back arrow closes the active session. Background helper availability and
  request notifications are retained, subject to iOS scheduling restrictions.
- iOS application messages are plaintext. BLE link encryption/authentication is
  unverified. Use non-sensitive iPhone demo text; do not claim encrypted iOS chat.
- `experiments/ble_poc` remains untouched. The abandoned interop worktree and its
  uncommitted work were preserved separately; none was imported here.

## Automated results on this Mac

Toolchain: Flutter 3.47.6 / Dart 3.13.5, Xcode 27.0 (27A266a).

| Check | Result |
| --- | --- |
| Android app `flutter analyze` | PASS, no issues |
| Android app `flutter test` | PASS, 36 tests including envelope and encrypted-session tests |
| Android `flutter build apk --debug` | BLOCKED: no Android SDK found |
| Android native unit tests | No native test sources in this baseline; Gradle build requires Android SDK |
| iOS app `flutter analyze` | PASS, no issues |
| iOS app `flutter test` | PASS, 37 tests including helper availability, transport channels and concurrent requests |
| Both transport packages `dart analyze` | PASS |
| iOS package `dart packages/relay_transport_ios/test/contract_test.dart` | PASS |
| Android package tests | Envelope/security contracts covered by Android app tests; no standalone package tests exist |
| Native Swift fixtures | PASS, all four groups below |
| iOS `flutter build ios --simulator --debug` | PASS, Xcode compilation |
| iOS `flutter build ios --release --no-codesign` | PASS, unsigned device-architecture compilation |
| iOS project / Info.plist `plutil -lint` | PASS |
| Website static checks | PASS, six groups including deployable ZIP |
| Chrome browser checks | PASS, 27 checks; widths 320, 390, 768, 1024, 1440 |
| JavaScript `node --check` | PASS, app and release config |
| Pages workflow | YAML parsed; integration branch/job guards and artifact step checked; hosted execution not run |
| `git diff --check` | PASS |

Native fixtures exercise all payload lengths 1–256, exact Hello/ACK vectors,
malformed framing, duplex receive state, PROFILE metadata, helper replay,
notification deduplication/authorization/cleanup, and concurrent central isolation.
Use the exact compile command in the root README; it includes
`BleCentralConnections.swift`, which the earlier handoff command omitted.

Website checks include keyboard flow, accept/reject/reset, no horizontal overflow,
reduced motion, no external resource requests, no runtime exceptions, local fonts,
GitHub Pages project-subpath loading and offline file fallback. This is Chromium
coverage, not a Safari/Firefox or physical-browser accessibility audit.

## Issues resolved

- **P0:** website static validation failed because intended arrows became `?`
  and the exclusion sentence disagreed with final scope. Corrected the content.
- **P1:** iOS lockfile still referenced the Android package path; corrected by
  Flutter dependency resolution to match the existing iOS pubspec.
- **P1:** missing integration record, incomplete native-test command and stale
  website/demo/security/deployment copy. Updated to the actual separate apps.
- **P1:** Pages workflow targeted main despite integration-only work. It now
  targets `integration/final-hackathon`, retaining scoped artifact/permissions.
- **P0 environment/manual:** Android APK generation needs an Android SDK host;
  public installation still requires actual APK hosting and Apple distribution.

## Security and distribution audit

Tracked text was scanned for private keys, common API/cloud/GitHub token patterns,
credential assignments, Apple team settings and local paths. No matching secret
material or signing credential files were found. Old machine-specific example
paths in current website instructions were replaced. This is a targeted scan,
not a guarantee that all historical Git objects contain no secrets.

No Apple team, provisioning profile, generated artifacts or app binaries are
committed. Android's existing release configuration uses a debug signing key;
label that artifact a demo, not a production-signed release.

Read-only GitHub checks found no release assets. Pages is configured with
`build_type=workflow`, but the public project URL returned HTTP 404. The recorded
earlier workflow failed at Pages setup. No new site deployment or app publication
was performed here. See [deployment](../../website/onya/DEPLOYMENT.md).

## Remaining demo gate

Earlier team-reported same-platform physical results remain historical evidence.
**This relocated integration build was not installed or physically tested here.**
Simulator success and unsigned compilation do not validate BLE.

1. On an Android SDK/JDK host, run the root README Android checks and build the
   debug APK. Install the same artifact on two Android 12+ devices. Record its
   source SHA and SHA-256; retain it outside Git. Publish a real Release asset
   only when approved, then configure and verify the website download URL.
2. On this Mac, open `apps/offline_relay_ios/ios/Runner.xcworkspace`, select a
   local team and sign/install on two iPhones. Keep signing changes local. For
   public access, the owner must configure Apple Developer/App Store Connect
   and an actual TestFlight/App Store distribution link.
3. On each same-platform pair: different names → helper enabled → discover →
   request → accept → send both directions → end/disconnect → reverse roles.
   Android must reach secure-chat readiness; iOS ends through the back arrow.
4. Verify Reject followed by a new request, helper disable, background request/
   notification/tap, and reconnect. With three iPhones, additionally verify two
   pending requests, first accept wins and losing-peer isolation.
5. After reviewing the website, authorize its publication from the integration
   branch; configure the Pages environment to permit it. Verify the returned
   HTTPS URL, downloads and mobile layout while signed out. Keep the packaged
   static site as a local judging fallback.

Do not test or build Android ↔ iPhone interoperability for this submission.
