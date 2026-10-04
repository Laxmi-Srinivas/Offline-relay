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

### Native/session follow-up after 451ebbe

| Gap and source at upstream 0d4e2c4 | Existing protection / prerequisites / impact | Minimal fix / evidence |
| --- | --- | --- |
| A6 native GATT queue: BleRelaySession.kt 91–122 (`clientOperations`, queue/run/done) | Nearby current peer supplies DATA notifications, causing queued ACK writes while a GATT operation is blocked. Individual frame/message caps and operation deadlines exist; the operation deque itself is unbounded. Medium, confirmed source growth; device exhaustion rate unknown. | A main-thread BleOperationQueue counts in-flight plus waiting operations, maximum 64; overflow follows existing connection-failure handling. Production queue tests cover FIFO, overflow, clear/replacement and 20,000 rejected operations; full APK compilation passed. |
| A7 detached replacement: BleRelayForegroundService.kt 79–109 attach snapshot; bridge incoming connection map | Existing snapshot filters historical messages, but does not retire Flutter's old helper connection after its disconnect was dropped while detached. Requires a disconnect/reconnect with the UI detached. Medium, confirmed channel regression; OS ordering remains pending. | Emit a current helperSnapshot before live events; prune ended helper connections only. Channel regression failed before fix, passes afterward. A lost-key accepted snapshot closes instead of approving a conversation with missing keys. The no-pending-request restoration regression also failed before its follow-up correction. |
| A8 alerts / stale send inspection: BleRelayForegroundService.kt 139–157 send completion, 259–288 request inspection, 296–330 outgoing inspection | First request is stable and service queue bounded to 64. Reconnect can raise a new alert without cooldown; old send completion need not match the service's replacement session. Low–medium; callback ordering uncertainty, no device exploit claimed. | Reuse tested monotonic 10-second RequestAlertGate across connections, keep suppressed requests in UI, scope session events/send completions to the current native session and connection, require matching pending request ID. Cooldown resets on service recreation; no claim of radio rate limiting. |

Paths for native references above are under
`apps/offline_relay/android/app/src/main/kotlin/dev/offlinerelay/offline_relay/ble/`.
Bridge path: `apps/offline_relay/lib/transport/ble_relay_transport.dart`.
All validations remain local/controlled; no unrelated devices or live services
were probed. Controller/native request parsing now agree on a nonempty string
name and offline_user role; tests reject invalid metadata and request replacement.

Follow-up verification: **60 Flutter tests passed**, analysis found no issues, and
debug APK build passed. Native runner passed its historical 6 deadline and 9
helper/buffer checks plus the new seven-operation/cooldown scenarios. Only the new
BleOperationQueue and RequestAlertGate are integrated in the current native path;
the old BleDeadlines/HelperConversation checks must NOT be presented as current
Android runtime coverage. Android framework/GATT policy is additionally compiled
by the full APK build, not simulated by those pure Kotlin tests.

Latest built APK SHA-256:
`2DE0748E217510C5E5FCA25D4920A693F3EFA344B7C1E3A920A830FB2D729CF8`.
Read-only historical secret-pattern triage checked 392 text blobs, skipped 37
binary blobs and found zero candidates in its five narrow pattern families.
No comprehensive secret-free or dependency-safe claim follows from that result.

The first integration commit included upstream font-license trailing whitespace
flagged by diff --check. This follow-up trims that whitespace and retains the
license text. The earlier commit was not amended or rewritten. Git check results
are guarded before the next commit; no iOS file is staged.

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

## Owned Android device verification (2026-10-04)

Source: Security `8bf78e2`, integrated Android/shared baseline
`0d4e2c4da1c81391d6aa33f49c60b291eab7198e`. Two owned Android 16 phones;
synthetic profiles SecurityA/SecurityB and synthetic ASCII chat only.
The original apps were retained with their data. Updating the original package
failed on both with INSTALL_FAILED_UPDATE_INCOMPATIBLE (different signing keys).
After explicit approval, installed a separate debug test package
`dev.offlinerelay.offline_relay.securitytest` successfully on both.
No uninstall, data clearing, device bond clearing or original app update occurred.

Test APK SHA-256:
`B67843D593A17AD1650B0EB461220FC862FD31C544C89E300A157B2624121101`.
Version 0.0.1 (code 1); apksigner verification passed, v2 signature present.
This is a local debug build, not a public beta release or the original tested APK.

| Check | Actual result / limits |
| --- | --- |
| Discovery and request | Requester discovered SecurityA. Helper displayed SecurityB request with Accept/Decline. No chat before approval. |
| Acceptance and key setup | Both reached encrypted-chat UI. Synthetic text delivered in both directions with both apps foreground. This exercises existing X25519/HKDF/AES-GCM setup; UI alone does not prove radio encryption or peer identity. |
| Reconnect isolation | After terminating the failed session, a newly approved connection opened empty on both phones; previous markers were absent. No physical old-ciphertext injection performed; automated crypto/session regressions cover that separately. |
| Intentional foreground end | Requester ended the replacement session; helper displayed Chat ended by SecurityB. |
| Background incoming request | Earlier request reached the background helper and was displayed after reopening. Notification appearance itself was not independently captured. |
| Rejection | No chat opened, but requester displayed GATT write_error status=133 instead of a clean decline message. Failed UX/recovery check; cause not established. |
| Background chat delivery | Helper was sent Home, requester sent a synthetic message, helper reopened. Message did not appear; requester displayed write_error status=1 and Connection lost, while helper initially retained chat UI. Failed delivery/state consistency check; do not claim background guarantees. |
| Limited logging/storage check | Requester's own current app PID logs (BLE/flutter/AndroidRuntime tags) contained no synthetic marker matches. Its files directory listed profileInstalled and shared_prefs was absent. This is not an exhaustive cache, backup or storage check. |

Commands/purpose: adb install -r (signature failure, then separate-package
success), aapt dump badging (package/version), apksigner verify --verbose
(signature), UI Automator plus input taps/text (local synthetic journey),
adb shell input keyevent 3 and am start (background/resume), own-package pidof
and scoped logcat marker filtering (limited logging), run-as test package ls
files shared_prefs (limited storage). Broad user notification logs were not read.
Vendor pm grant was denied; normal app permission dialogs were used, with no
permission safeguard disabled. Bluetooth was enabled on the requester for this
local check. Device serials, raw UI dumps, APKs and signing keys are not committed.

Reproduce the separate package without modifying tracked mobile build files:
use the documented init script in `test/native/security-test.init.gradle`, from
apps/offline_relay/android after the normal Flutter debug build/setup:

```powershell
./gradlew.bat --init-script ../test/native/security-test.init.gradle assembleDebug '-Ptarget-platform=android-arm,android-arm64,android-x64' '-Ptarget=lib/main.dart' '-Ptrack-widget-creation=true'
```

Verify output package with aapt before installing
build/app/outputs/apk/debug/app-debug.apk. A first direct Gradle attempt without
quoting the -Ptarget argument failed in PowerShell; quoted retry succeeded.
Direct Gradle emitted existing Android/Kotlin configuration deprecation warnings.

Next: reproduce rejection and background GATT errors under controlled foreground,
background and reconnect conditions before changing transport timing or lifecycle.
Late native errors must also be checked for connection scoping. No root cause or
fix is claimed from a generic GATT status alone. BLE link security, active MITM,
physical malformed/replay/flood tests and exhaustive logs/backups remain pending.
These failures and uncertainties are retained rather than counted as passed.
