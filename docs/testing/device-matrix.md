# Device matrix and acceptance evidence

No physical-device tests have been performed. All combinations below are targets
or candidates, not supported-platform claims. Record exact hardware, OS, app
revision, role assignment, permissions, and logs for each run.

| Device combination | Candidate | Current evidence |
| --- | --- | --- |
| Android 12+ ↔ Android 12+ | BLE, test both role assignments | Native source prepared; APK blocked; not tested |
| Android ↔ iOS | BLE, test both role assignments | Not tested |
| iOS ↔ iOS | BLE | Not tested |
| Linux/macOS/Windows laptops | LAN, each actual pair separately | Not implemented/tested |
| Phone ↔ laptop on shared LAN | Possible later extension | Unverified, not initial POC |

## BLE run procedure (after implementation)

1. Install on two physical phones. Record models and OS versions. Keep apps open.
2. Turn Internet access off on the sender while leaving Bluetooth enabled.
3. Start peripheral/service advertising, then central discovery. Select the peer.
4. Capture discovery started, device discovered, connection established,
   service discovered, and characteristic discovered logs.
5. Send `Hello`; require message sent, exact message received, and matching ACK
   received logs. Capture evidence from both phones.
6. Repeat with a deterministic 256-byte payload; compare all bytes and ACK ID.
7. Disconnect; record raw platform status/error and local reason where known.
8. Swap roles. Test permissions denied, Bluetooth off, peer absent, disconnect
   during transfer, and missing ACK. Failures must terminate with useful logs.

A simulator, a mock, a unit test, or a successful build is not BLE evidence.
Unit tests can validate framing/reassembly/timeouts only.

## Initial host inspection

2026-10-04: Linux host. Flutter and Dart absent from PATH. Java, CMake and
pkg-config detected; adb, clang, ninja and GTK 3 development metadata not found.
No Android SDK found in the checked standard locations. Apple and Windows build
toolchains cannot be validated on this host. Toolchain setup and build results
must be recorded separately from device results.

Flutter 3.47.6 was subsequently obtained in `/tmp`. See the
[validation record](validation.md) for passed Dart/Flutter checks and failed
native build attempts. No runnable BLE platform has been verified.
