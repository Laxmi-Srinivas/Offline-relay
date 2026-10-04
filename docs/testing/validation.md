# Validation record — 2026-10-04

Task status: **BLE POC and Android product transport physical validation passed**.
The product UI, service-request flow, and BLE negative-case matrix remain
unverified.

## Environment

- Fedora Linux 43, x86_64; only Linux desktop was listed as a device.
- Flutter 3.47.6 stable, revision `5fc346839b`; Dart 3.13.5.
- SDK cloned to `/tmp/offlinerelay-flutter-sdk`; not on PATH and may disappear
  on temporary-directory cleanup.
- Android SDK/adb absent. Java present. Linux lacks Ninja, clang++ and GTK 3
  development libraries according to `flutter doctor -v`.
- No physical phones connected. No macOS or Windows build host.

## Results

Commands used the absolute temporary SDK path. Locations below identify each
command's working directory.

| Location | Command | Result |
| --- | --- | --- |
| Host and POC | `flutter pub get` | Passed; lockfiles created |
| `apps/offline_relay` | `flutter analyze` | Passed, no issues |
| `experiments/ble_poc` | `flutter analyze` | Passed, no issues |
| Repository root | `dart analyze packages/relay_transport` | Passed, no issues |
| `apps/offline_relay` | `flutter test` | Passed, 1 host smoke test |
| `experiments/ble_poc` | `flutter test` | Passed, 2 diagnostic channel tests |
| Host and POC | `flutter build bundle --debug` | Passed; Flutter bundles only |
| `experiments/ble_poc` | `flutter build apk --debug` | Failed: no Android SDK found |
| `apps/offline_relay` | `flutter build linux --debug` | Failed: Ninja unavailable; CMAKE_CXX_COMPILER not set |
| Apple/Windows targets | Native build | Not run: appropriate host toolchain unavailable |
| BLE pairs | Discovery, Hello, larger payload, ACK | Not run: no physical-device evidence |

Initial analysis attempts hit sandbox restrictions on Dart/Flutter cache writes;
reruns with approved tool access passed. A formatting check flagged the new POC
test file, which was subsequently formatted. Native Kotlin analysis/compilation,
Android lint, and native framing tests have not run. Flutter analysis/tests do
not cover them. Mock channels in the diagnostic tests are explicitly not
networking success evidence.

## Physical Android BLE POC — 2026-10-04

The existing POC debug APK was installed on two authorized physical Android 16
(API 36) phones: OPPO CPH2729 (`8fb67c3d`) and Realme RMX3998IN
(`YDPV6TFMBY85RCJN`). Nearby Devices permissions were granted on both. No
application implementation files were changed for this validation.

The runbook passed in both directions:

| Central | Peripheral | Advertising, discovery, connection | Hello + application ACK | 256-byte transfer + ACK | Stop/disconnect |
| --- | --- | --- | --- | --- | --- |
| OPPO CPH2729 | Realme RMX3998IN | Passed | Passed; `Hello`, ID 1, 5 bytes | Passed; ID 2, 16 frames, exact `00..ff`, 256 bytes | Passed; `user stop` on both |
| Realme RMX3998IN | OPPO CPH2729 | Passed | Passed; `Hello`, ID 1, 5 bytes | Passed; ID 2, 16 frames, exact `00..ff`, 256 bytes | Passed; `user stop` on both |

The peripheral logs reported `message_received ... exact_payload_verified=true`
for both payloads and submitted each application ACK; the central logs reported
matching `acknowledgement_received` IDs and lengths. Advertising, device
discovery, connection, and data/ACK characteristic discovery were logged in
each direction. Timeout behavior was not tested. The logs were collected with
`adb logcat -v time OfflineRelayBLE:I '*:S'` on both devices.

## OfflineRelay Android product transport - 2026-10-04

The production host adapter APK was built with Flutter 3.47.6 and installed on
the same two Android 16 (API 36) phones. The transport reused the validated POC
service and characteristic UUIDs, 16-byte framing, sequential GATT writes,
reassembly, 256-byte message cap, and application ACK format. Discovery used a
service UUID scan filter. Both apps remained in the foreground.

OPPO CPH2729 advertised its profile. Realme RMX3998IN discovered it, connected,
and completed service/characteristic discovery. OPPO surfaced an incoming
connection. The phones then exchanged these arbitrary protocol envelopes in
both directions; both sends completed with the BLE transport application ACK:

```json
{"version":1,"id":"4264eeae9e770ed8a1ba4cf565d1cb04","type":"chat","body":{"text":"Generic OfflineRelay JSON over BLE"}}
{"version":1,"id":"f9581d450dd05e78681804c83a99878b","type":"connection_accept","body":{"requestId":"4264eeae9e770ed8a1ba4cf565d1cb04"}}
```

Realme logged exact receipt of the 120-byte chat envelope and OPPO logged exact
receipt of the 136-byte reverse envelope. Native logs recorded the matching
message lengths and `acknowledgement_received` on both devices. This validates
the Android host adapter on these devices, not the Nearby/Chat UI or the full
negative-case device matrix.

## Required next environment work

The BLE POC and Android product host debug APKs and their described physical
tests are verified. Timeout behavior and the full negative-case
[device matrix](device-matrix.md) remain to be tested. Product UI, chat and
service-request flows are not implemented. iOS/macOS and Windows product-host
builds have not been validated. These remaining checks do not change the BLE
results above.
