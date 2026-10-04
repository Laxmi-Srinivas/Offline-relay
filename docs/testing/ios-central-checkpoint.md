# iOS central implementation checkpoint — 2026-10-04

Branch: `ios-mvp`, based on Android physical checkpoint `6128998`.
No commit or push performed. The product host and shared transport contract
remain unchanged. iOS code lives only in `experiments/ble_poc/ios`.

## Build and tests

Mac SDK: Flutter 3.47.6, Dart 3.13.5, Xcode 27.0 (27A266a), iOS SDK 27.0.

| Check | Result |
| --- | --- |
| POC `flutter analyze` | Passed, no issues |
| POC `flutter test` | Passed, 2 existing channel tests |
| Product placeholder `flutter analyze` | Passed, no issues |
| Product placeholder `flutter test` | Passed, 1 existing smoke test |
| `dart analyze packages/relay_transport` | Passed, no issues |
| Swift framing helper + `test/native/main.swift` | Passed: exact Hello, all 00..ff frames, ACK lengths/IDs, boundaries, ID rollover |
| POC `flutter build ios --simulator --debug` | Passed; `build/ios/iphonesimulator/Runner.app` |
| `git diff --check` | Passed |
| `xcrun devicectl list devices` | No devices found |

Native byte tests execute the same `BleProtocol.swift` used by the central. They
provide no radio, delegate lifecycle, or timeout evidence. The simulator build
provides compilation evidence only. No physical iPhone/Android run occurred.

## Android preservation

Before changes, Android-related diff against HEAD was empty and recorded at
`/private/tmp/offlinerelay-android-baseline.diff`; tracked index entries were
recorded at `/private/tmp/offlinerelay-android-baseline-index.txt`.
Final Android diff is empty and byte-identical to the baseline. Tracked Android
files are also compared byte-for-byte with HEAD. No new Android files are present.
Both `experiments/ble_poc/android` and `apps/offline_relay/android` are covered.

## Remaining hardware setup

No DEVELOPMENT_TEAM is configured in the experimental Runner project. Open
`experiments/ble_poc/ios/Runner.xcworkspace`, select a valid signing Team, and
provision bundle ID `dev.offlinerelay.experiments.blePoc`. Connect/trust an iPhone
and enable Developer Mode if required. Then deploy the POC to the physical device.

Run Android peripheral / iPhone central with Hello and 256 bytes, capturing both
phones' exact receipt and ACK logs. Also test absent peer, denied permission,
Bluetooth off, missing ACK, interrupted transfer, foreground exit, stop/restart,
and deadline/stale-callback behavior. No physical BLE success is claimed.

iOS peripheral is not implemented. The first two-platform test uses the validated
Android peripheral. Protocol UUIDs, 16-byte payload chunks, version 1, ID cycle,
write-with-response sequencing, and four-byte big-endian-length ACK are unchanged.
