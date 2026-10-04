# Validation record — 2026-10-04

Task status: **incomplete at native build/device validation**. Source and
documentation are prepared; no installable target or physical BLE exchange has
been verified. Development stopped at the native toolchain blocker.

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

## Required next environment work

Provide an Android SDK with the platform/build tools required by the generated
Flutter project and complete its license setup. Re-run the APK build, resolve
any native compiler/lint findings, then use two physical Android 12+ phones to
execute the [runbook](../../experiments/ble_poc/README.md). Confirm the actual
phone models and their role support; neither role is assumed from OS version.

For the foundation's Linux native build, install Ninja, clang++ and GTK 3
development prerequisites, then rebuild. iOS/macOS and Windows need their own
build hosts. These blockers are not evidence that BLE is impossible on any of
the intended platforms.

No commits, pushes, production features, or system package installations were
performed. The original Git repository and remote remain in place.
