# Current encrypted Android security work

This document supersedes older Android implementation descriptions, not their
historical test records. Work branch: Security. Source imported with user approval:
origin/main `0d4e2c4da1c81391d6aa33f49c60b291eab7198e`, authored by the upstream
team. Main remains read-only; no branch merge, history rewrite or iOS import.
Only existing Android/shared code, assets, declared dependencies and relevant
tests were copied. Earlier Security commits remain ancestors. Prepared Swift
changes and their native test file remain uncommitted and untouched.

## Implementation and trust

| Feature | Source evidence at 0d4e2c4 | Verification | Review now |
| --- | --- | --- | --- |
| Discovery, helper availability, request/approval/notifications | Android MainActivity and ble/BleRelayForegroundService; controller | Existing code; user-reported Android-to-Android tests | Yes |
| Encrypted chat and encrypted End Chat | lib/security/relay_secure_session.dart; controller | Local tests/build below | Yes |
| Report | Controller submitLocalReport / UI | Temporary in-memory reason/note, no moderation server | Yes |
| iOS | Separate native adapter / prepared changes | Not validated by this Android work | Deferred |
| Presentation website | feat/onya-presentation | Separate deployment/tests | Outside this mobile work |
| Accounts/database/Internet relay/orders/rides | No implemented flow | Not implemented | No |

Requester/helper names and roles remain self-asserted. Consent belongs to a
particular current connection/request. A BLE connection alone cannot authorize
chat. After acceptance, standard cryptography 2.9.0 primitives provide fresh
X25519 keys, directional HKDF-SHA-256 keys, AES-256-GCM and encrypted confirmation.
Counters/directions are authenticated; reconnect creates fresh keys. This is an
automatic, unauthenticated key exchange: an active intermediary can substitute
keys. Do not claim authenticated identity or active impersonation resistance.
BLE identifiers, request metadata, lengths/timing remain visible. No second
encryption system or custom algorithm was added by this work.

## Confirmed gaps at the upstream snapshot

All controller references below are
`apps/offline_relay/lib/relay_demo_controller.dart` at 0d4e2c4. Medium severity
means a practical session disruption or aggregate memory growth, not demonstrated
remote code execution or disclosure.

| Finding | Evidence / reachable path / protection | Impact, confidence, fix and validation |
| --- | --- | --- |
| A1 stale restored approval | Controller 575–593 `_onHelperAccepted`; native approval -> bridge -> controller. Existing terminal/inChat guard; approval does not match connection/request. Peer cannot forge channel events directly; requires delayed native snapshot/event. | Medium, high source confidence: old approval closes replacement B or corrupts its state. Match the live connection object and pending request before handling lost-key restoration. Negative controller tests failed upstream; real channel tests pass. OS ordering still needs devices. |
| A2 unbounded decrypted history | Controller 390–411 `sendChat`, 802–825 decrypted chat append. Approved peer supplies valid encrypted messages; per-envelope 256-byte cap and authenticated counters exist. | Low–medium, confirmed growth; exhaustion rate unknown. Retain newest 300 local/incoming messages, with a UI explanation. Both 310-message encrypted tests fail upstream and pass after fix. |
| A3 unbounded asynchronous receive chain | Controller 595–620 `_listenForMessages`. Current peer delivers envelopes while receive/key exchange awaits. Serial processing and byte caps do not cap pending work. | Medium, high source confidence: increasing queued input; practical radio rate unknown. At most 64 pending envelopes (each <=256 bytes); overflow closes only that connection. Reject bad byte lengths before queueing, invalidate old work on session change. Controlled burst regression fails upstream and passes after fix; not radio flood evidence. |
| A4 late connect/accept after leaving | Controller 262–288 connect completion and 332–364 accept; awaited operations can finish after Return to Nearby. Existing disposed/cancellation and some key-session guards exist. | Medium, high confidence: an old operation reinstalls a connection/chat or raises stale errors. Session epochs and current-connection guards stop obsolete completions; security failures carry the offending connection instead of closing whatever replaced it. Late connect/accept regressions fail upstream and pass after fix. |
| A5 retained editor draft | `apps/offline_relay/lib/ui/screens/chat_screen.dart` 24–37; editor disposed only when the widget is destroyed. Requires reuse after terminal chat. | Low, confirmed widget regression: private draft can appear for another peer. Clear the editor when the chat is terminal/inactive. Regression fails upstream and passes after fix. |

Safe validation uses synthetic messages and local fake transports for the above;
only owned phones may be used for real BLE tests. No external scanner is used.

## Actual local verification

- Initial import helper refused the wrong working directory without writing.
  The subsequently run 38-test suite was the OLD source, not new-build evidence.
- Import then succeeded on Security. Offline dependency resolution failed because
  cryptography was not cached; normal `flutter pub get` acquired the declared
  packages. No extra dependency or algorithm was introduced.
- The first mixed suite failed: old tests assumed plaintext chat, old UI and old
  snapshot semantics. Original sources are retained in legacy-tests/*.dart.txt;
  executable tests now exercise encryption, fail-closed key loss and current UI.
  They are not counted as the earlier 38 tests plus all upstream tests.
- Negative check against upstream controller/bridge: 4 passed, 9 failed. In-progress
  Security source was saved and restored byte-for-byte in a finally block; no
  other checkout/index/history was touched. Log: TEMP/Onya-upstream-negative-tests.log.
- Final `flutter test --reporter expanded`: **57 passed**, including original
  upstream behavior tests plus adapted/new regressions. Extra crypto tests reject
  old-session ciphertext, reflected keys, wrong direction/counter tampering and
  authenticated out-of-order packets. AEAD tampering/replay failures close chat.
- `flutter analyze`: no issues, after correcting six brace-style lint notices.
- `flutter build apk --debug`: passed, including Kotlin/Gradle. Java native-access
  warnings remain tooling notices. This is debug signing, not production release.
- Built APK SHA-256: `27C42519CF0D681297D2C4002BA93920A42B1666040F34B3A5E0061862FE313E`.
  Device installation and security behavior are not established by this build.

Commands ran in apps/offline_relay using cached Flutter 3.47.6 / Dart 3.13.5.
Raw local logs are under TEMP/Onya-android-*.log, not committed device dumps.

## Connected phones and existing APK scope

Owned devices CPH2729 and RMX3998 both report Android 16, app version 0.0.1,
versionCode 1, debug signing/build flags, Bluetooth and notification permissions.
Source pubspec at upstream is 0.0.1+1. Matching version is NOT matching source.
Installed APK hashes differ:

- CPH2729: `ed894ba0c4308eceec8b40453d7b2b4bb5df45e25a6f873f8f8b0f28d79afe68`
- RMX3998: `3c88725d3a740911374c50b19d833a6437489c9f9855afc185e0421d78e929b9`

User reports Android-to-Android testing complete; exact tested source and security
test cases have not been supplied. No raw device serials are recorded here.
Read-only app-directory listings found profileInstalled in files; CPH2729 had no
shared_prefs directory. RMX3998's shared_prefs listing was empty. No contents were
read. This is not a complete storage/backup audit. Both installed manifests allow
backup and are debuggable; no chat backup leak has been demonstrated.

## Remaining work and limits

Native operation queue/notification/session policy review, final APK install and
owned-device security checks continue next. BLE link encryption/authentication,
active-intermediary protection, framework storage/logs/backup behavior and practical
radio flooding remain unverified. Release uses template debug signing; public beta
requires a separate signing/release decision, no secret committed to Git.

The maintainer advisory page for Dart cryptography had no published advisories;
issue #224 concerns reported CBC/CTR issues, not evidence of a version-matched
AES-GCM/X25519 vulnerability here. No known-vulnerable dependency finding is asserted:
https://github.com/dint-dev/cryptography/security/advisories
https://github.com/dint-dev/cryptography/issues/224
This is bounded primary-source triage, not comprehensive advisory coverage.
