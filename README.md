# OfflineRelay

OfflineRelay is an Android offline peer-to-peer chat demo over Bluetooth Low
Energy. Flutter owns profile/request/chat UI and ephemeral encryption; native
Android GATT handles discovery, bounded messages, fragmentation and transport
ACKs. A connected-device foreground service keeps Help Others available while
the helper uses another app and shows incoming request notifications.

Requester: enter a name in Profile, find nearby helpers, request a connection,
wait for acceptance, and chat after automatic encrypted session setup.
Helper: enter a name, enable Help Others, open an incoming notification, and
accept or decline. Key exchange and encrypted key confirmation are automatic;
neither user sees codes or cryptographic material.
Chats and reports remain in memory; reports are not sent to a moderation service.

## Repository

- `apps/offline_relay/`: current Android Flutter product/demo.
- `packages/relay_transport/`: transport boundary and 256-byte JSON envelopes.
- `experiments/ble_poc/`: frozen validated diagnostic reference, independent of
  the product. Its original runbook describes its historical milestone.
- `docs/`: architecture, protocol, security and validation records.

## Build and run

Use Flutter 3.47.6 / Dart 3.13.5, an Android SDK, and a compatible JDK/Gradle
installation. From `apps/offline_relay/`:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter devices
flutter run -d DEVICE_SERIAL
```

From the repository root: `dart analyze packages/relay_transport`.
Install the same debug APK on both physical phones, keep Bluetooth enabled,
and grant Nearby devices. Help Others additionally requires enabled Android
notifications, including its Nearby help requests channel. Runtime BLE support
requires Android 12+ (API 31); helper hardware must support advertising.
No location access, backend or Internet connection is needed for BLE chat.
The platform scaffolds for iOS/desktop do not implement this BLE adapter.

## Reliability and validation

See the [deployment audit](docs/testing/deployment-readiness.md),
[physical validation history](docs/testing/validation.md),
[device matrix](docs/testing/device-matrix.md),
[architecture](docs/architecture/overview.md),
[protocol](docs/protocols/message-protocol.md), and
[encryption design](docs/security/e2e-chat.md).

This is a hackathon demo, not a production release. Requester connections stop
when the app leaves the foreground. Helper availability is service-owned but
cannot survive Android force-stop/process death. Profiles/messages/keys are
not persisted; reconnect starts a fresh session. Real Activity/engine recreation
can close an accepted chat; normal rotation retains the existing Flutter state.
Messages must fit a complete 256-byte envelope, so keep them short.
Release signing still uses debug keys and needs a separate release setup.
Encryption does not authenticate an unknown person's identity or prevent an
active man-in-the-middle from impersonating a peer.
Do not commit APKs, toolchains, device logs, caches or build output.
