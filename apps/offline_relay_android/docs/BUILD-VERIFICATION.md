# Build and device verification

Last updated: 2026-10-04. App version: 0.3.3 (versionCode 6).

## Current local verification

Ran from the repository root with JDK 17 and Gradle 8.13:

```text
:app:assembleDebug       BUILD SUCCESSFUL
:app:testDebugUnitTest   42 tests, 0 failures, 0 errors, 0 skipped
:app:lintDebug           BUILD SUCCESSFUL, 0 errors, 13 warnings
```

The commands verify compilation, JVM protocol/session behavior, and static Android checks. They do not test Nearby radio behavior or prove the end-to-end phone flow.

Lint warnings are about the pinned target/toolchain versions, backup configuration, the missing launcher icon, and a KTX style suggestion. No lint errors were reported. Dependency upgrades and adding a production launcher icon are outside this verification-only change.

## Physical-device evidence and remaining check

Phones used earlier: Oppo K13 and Realme 9 Pro. Earlier screenshots showed the Oppo reaching the ready state and the Realme reporting Nearby `8033: MISSING_PERMISSION_CHANGE_WIFI_STATE`. The manifest declaration was corrected in version 0.3.2. Later user-provided logs on the Realme showed the app had coarse, fine, and nearby-device permissions granted while Nearby still reported `8034: MISSING_PERMISSION_ACCESS_COARSE_LOCATION`; the user also saw a fine-location permission error on the Oppo.

Version 0.3.3 is a candidate that requests coarse and fine location at runtime and declares both without an SDK cap. It also includes the v0.3.2 Wi-Fi permission correction. **This candidate has not yet been checked on either phone.** The requester → request → accept/decline → chat → end flow remains unverified on physical devices. Do not present phone networking as passing until the checklist in [DEVICE-CHECK.md](DEVICE-CHECK.md) succeeds on the same build.

## Automated test coverage

The 42 JVM tests cover message validation and fake-transport session behavior, including the HELLO gate, request, acceptance, decline, bidirectional chat, end, invalid ordering, timeout, disconnect, retired callbacks, and malformed or unexpected payloads. These tests do not simulate Android permissions, Google Play services behavior, or Nearby Connections radios.

## Known prototype limits

- Task and chat content live in memory for the active session. There is no database or saved history.
- If the Nearby connection is lost or Android kills the process, the task does not resume; the phones need a new session.
- There is no cloud service, account, real-world identity check, attachment, booking/payment integration, mesh, or multi-hop relay.

## Next physical test

Use the same 0.3.3 build on both phones, with Wi-Fi and Bluetooth on and mobile data off. Follow [DEVICE-CHECK.md](DEVICE-CHECK.md). First confirm that both phones can advertise, discover, connect, and reach READY; only then test help request, accept/decline, chat in both directions, and ending the session. Capture the exact error and device Android version if either phone fails.
