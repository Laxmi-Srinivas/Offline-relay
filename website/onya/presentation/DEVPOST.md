# Devpost draft — onya

Draft only; nothing submitted. The team must check event-specific eligibility,
prior-work/AI disclosure, required fields and video rules before submission.

## Inspiration

When campus Internet disappears, nearby people can still choose to help. Onya
comes from “good on ya”: recognizing that choice. Our hackathon scope is a simple
nearby conversation, not an Internet relay or automatic task marketplace.

## What it does

Two Android phones or two iPhones discover, request, accept/reject and exchange
short text over BLE without a central chat server. Both phones need the app
installed beforehand. Android ↔ iPhone is outside this submission's scope.

The website explains the project and installation paths using a clearly labelled
browser simulation. It does not connect to phones or demonstrate physical radio
behavior. Public download controls stay hidden until real releases are available.

## How we built it

We preserved separate Flutter app targets: Kotlin/GATT on Android and native
Swift/CoreBluetooth on iOS. Each uses its existing 256-byte envelope, fragmentation,
ACK and lifecycle implementation. The iOS app retains concurrent outgoing requests,
first accept wins, background helper availability and local request notifications.

Android uses ephemeral X25519, HKDF and AES-GCM for chat/End Chat. It does not
bind keys to authenticated peer identities; active impersonation remains possible.
The preserved iOS baseline exchanges plaintext application envelopes, so the demo
uses non-sensitive text. Bluetooth link protection is unverified. Neither build
is claimed production-secure.

The website uses HTML/CSS/JavaScript, local fonts and SVG assets without a backend,
tracking, external APIs or cloud messaging. It can be presented locally offline.

## Verification and lessons

Current Mac checks: 36 Android and 37 iOS Flutter tests pass; both analyses pass;
iOS transport contracts and native Swift fixtures pass. The separate iOS app
compiles for simulator and unsigned device release. Website static checks and 27
Chrome browser checks pass, including responsive layouts and offline fallback.

The Android app is unchanged from its existing baseline, but this Mac lacks an
Android SDK, so a fresh APK build remains required on a configured host. Earlier
team-reported physical results are distinct from fresh integration validation;
see the repository's final integration record before claiming device success.
Historical Security-branch reports are archived evidence, not changes imported
into this final build. We learned to preserve working implementations, state
security limits accurately, and separate build evidence from radio behavior.

## Remaining before submission

- Rehearse and record the final same-platform phone demonstrations.
- Build/verify/host the Android APK; retain its source SHA and hash.
- Sign the iPhone demo locally, or finish Apple Developer/App Store Connect and
  TestFlight/App Store distribution. No public Apple link is currently configured.
- Publish the approved static site and verify its returned HTTPS URL; current
  expected Pages URL returns 404 despite Pages being configured.
- Confirm event eligibility, authorship/prior-work allowance, deadlines, AI/tool
  disclosure, sponsor criteria, video duration and signed-out playback.

## Assets and tags

- Repository: https://github.com/Laxmi-Srinivas/Offline-relay
- Website: pending successful publication; do not submit localhost or a 404 URL.
- Video: record/upload a real approved demo; no invented link.
- Cover: `../assets/devpost-cover.png`, 1200 × 800 project illustration, not an app
  screenshot. Use the runbook for narration and device steps.
- Technologies actually used: Flutter, Dart, Kotlin, Swift, CoreBluetooth,
  Bluetooth Low Energy, HTML, CSS, JavaScript.
