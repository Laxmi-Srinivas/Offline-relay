# Deployment-readiness audit — 2026-10-04

Baseline: `main`, `67acd0632eb1965482d7b745e06f1ef0c83b55f5` (Phase 1 UI).
The working tree already contained uncommitted secure chat, report/end-chat UI,
the cryptography dependency, and protocol/security documentation when this audit
started. Those changes were preserved and audited as part of the current app.
No POC source or configuration was modified.

Product correction: human code verification has been removed. The current
automatic-encryption revision has subsequently been manually validated by the
user on physical Android devices. The final branding checkpoint preserves that
functional state. Its Flutter analysis passed with no issues and all 36 Flutter
tests passed. Earlier agent device observations below predate the correction;
no additional physical-device tests are performed for this final checkpoint.
The final `flutter build apk --debug` also succeeded. The ignored output is
`apps/offline_relay/build/app/outputs/flutter-apk/app-debug.apk`. Supplied symbol
artwork provides adaptive/themed launcher icons and all five legacy densities;
the supplied horizontal artwork replaces the Home header placeholder. The
OfflineRelay name and application ID are preserved.

## Product behavior

The requester enters a name, searches Nearby, chooses a helper, sends a request,
and waits for acceptance. The helper enters a name and enables Help Others.
Android's connected-device foreground service owns helper advertising and the
peripheral connection. An incoming request produces a normal Android notification;
tapping it opens the app and restores the pending request for accept/decline.
After acceptance, both phones automatically establish encryption and confirm
session keys internally, then exchange short encrypted chat messages. End Chat
uses the encrypted session. There is no code or human verification stage.
Report records a reason/note locally in memory and sends nothing to a backend.

## Fixes from the audit

- Retain discovered peer handles after the scan window; allow selection after
  discovery stops. StopDiscovery no longer cancels a connecting GATT deadline.
- Serialize central GATT data writes, ACK writes, and ACK reads so overlapping
  bidirectional traffic does not collide with Android's single-operation queue.
  Keep connection, send/ACK, ACK-write, and reassembly deadlines independent.
- Serialize application sends and encryption counters; protect against repeated
  acceptance and concurrent connect/accept/reject operations.
- Automatically exchange ephemeral keys and encrypted key confirmations.
  Keep the public key available when peer key exchange arrives before its send.
- Bound requests to 60 seconds and automatic encrypted setup to two minutes.
  Requests also expire in the native helper service while its Activity is absent.
- Clean up failed request sends, requests disconnected before their first envelope,
  rejection, cancellation, radio shutdown, and terminal chat sessions.
- Restore pending helper requests from the live service snapshot; bound native
  event queues and avoid replaying disconnected sessions. Do not reuse lost keys
  when a Flutter engine is recreated after acceptance.
- Preserve helper availability when a Flutter engine detaches. Native service
  failures report disabled availability; permission requests and pending channel
  results cannot overwrite each other or complete twice.
- Require visible app/request notifications for helper mode, explain Settings
  recovery, and avoid destroying discovery merely because a permission dialog
  stops the Activity.
- Preserve the existing visual style, scroll terminal/security screens in
  landscape, handle narrow headers, route Done to Nearby, intercept chat Back,
  show the newest messages, and retain the composer draft when sending fails.
- Reject oversize encrypted messages with a useful error. Never truncate chat
  content. Remove exception details from native JSON inspection logs.

## Verification

Windows host: Flutter 3.47.6, Dart 3.13.5; local Android SDK and Gradle toolchain.
`flutter analyze`: passed, no issues. `flutter test`: passed, 36 tests.
`flutter build apk --debug`: passed, including Kotlin compilation.
Physical-device results are recorded below after execution. Unit/widget tests
are not BLE or native radio evidence.

## Limits

- Android 12+ only for BLE; the helper phone must support peripheral advertising.
  Other platform scaffolds have no BLE implementation.
- Requester discovery/chat is Activity-owned and stops when leaving the app.
  Helper availability survives leaving the Activity, but process death,
  force-stop, OS service stop, and permission revocation can end availability.
  It is intentionally non-sticky: reopen and explicitly enable Help Others.
- Rotation is handled by Flutter's existing manifest configuration-change flags.
  Genuine Flutter engine loss clears chat keys/history; a restored accepted
  native connection is closed and a new session is required. No automatic retry.
- Names, chat, reports and keys are in memory. No persistent accounts/profile,
  identity verification, moderation service, offline delivery, Internet checks,
  or automatic reconnect exist.
- The complete envelope remains at most 256 UTF-8 bytes. Emoji and JSON escaping
  reduce available chat length; the UI's 80-character limit is only an upper
  bound. Send failure preserves the draft. ACK confirms transport receipt, not
  that the remote user read the message. Delivery is uncertain on a lost ACK;
  there is no silent automatic resend.
- Peer identity is not authenticated. Active man-in-the-middle impersonation
  is not prevented. This is an unaudited hackathon encryption protocol; see
  `docs/security/e2e-chat.md`.
- Release builds currently use the template debug signing configuration. This
  stage creates a debug demo APK, not a Play Store release.
- Static checks found no tracked credentials/private keys, plaintext chat/key
  logging, or tracked APK/build output. App debug/profile manifests retain
  Flutter's development INTERNET permission; the main manifest has no Internet
  permission and no location permission. Build output and local audit evidence
  are ignored. This inspection is not a complete historical secret audit.

Android permission/service references:
[Bluetooth permissions](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions),
[connected-device foreground services](https://developer.android.com/develop/background-work/services/fgs/service-types#connected-device).
