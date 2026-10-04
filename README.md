# OfflineRelay Flutter chat

This branch contains the implemented Flutter Android nearby-peer text chat:
BLE discovery, connection requests, explicit approval, and in-memory conversations.
Android Help Others uses a foreground service and request notifications while the
UI is detached. No accounts, backend, Internet relay actions, database, website
or LAN transport are implemented here. Names/roles are self-asserted; private,
authenticated transport has not been demonstrated by this security work.

## Layout

- `apps/offline_relay/`: Nearby/Chat UI, controller, Android bridge and native GATT
  adapter/background service. Other platform folders on this branch are scaffolds.
  Committed iOS implementation was selectively imported from `ios-mvp` for
  authorized hardening; native fixes await Mac verification (docs/security/IOS.md).
- `packages/relay_transport/`: transport-independent interfaces and bounded JSON
  envelopes. Android's platform adapter lives in the application.
- `experiments/ble_poc/`: separate Android 12+ central/peripheral experiment.
  The product host has no dependency on it.
- `docs/`: [scope](docs/product/v1-spec.md),
  [architecture](docs/architecture/overview.md),
  [transport constraints](docs/architecture/transports.md),
  [ADR](docs/decisions/ADR-001-transport-architecture.md),
  [protocol](docs/protocols/message-protocol.md), and
  [device evidence](docs/testing/device-matrix.md).
- `docs/security/`: [findings and architecture](docs/security/README.md),
  [executed commands](docs/security/COMMANDS.md), [reproducible checks](docs/security/VERIFICATION.md)
  and [targeted audit](docs/security/AUDIT.md). Design plans in older documents are
  not evidence that a feature exists.

## Toolchain and commands

Generated with Flutter **3.47.6**, Dart **3.13.5**, framework revision
`5fc346839b`. A temporary SDK was obtained from the official Flutter stable
repository; it is not part of the repository. Put a matching Flutter SDK on PATH to use the
commands below. See [Flutter installation](https://docs.flutter.dev/install/manual).

Run in each Flutter project directory:

```sh
flutter pub get
flutter analyze
flutter test
flutter build bundle --debug
```

The bundle command compiles Flutter assets/Dart only; it does **not** validate
native platform code or produce an installable app. With platform prerequisites
installed, build the host using `flutter build linux --debug` or
`flutter build apk --debug`; Apple/Windows targets require their respective
host toolchains. Run `dart analyze packages/relay_transport` from the repo root.

For the BLE experiment, see its [runbook](experiments/ble_poc/README.md).
Contributor device evidence is in the [validation record](docs/testing/validation.md).
Security's shared Flutter tests and Android native source compilation have passed;
its debug APK build passed after resolving initial SDK/disk-space failures.
iOS native fixes await Mac verification. Background/negative-case physical checks and link
encryption/authentication remain pending. See the security verification record
for exact outcomes and limitations; prior device records were not rerun here.

## Dependencies and Git

Both apps use Flutter, Flutter's test SDK, and `flutter_lints` 6.x. The host also
references the local `relay_transport` package. There are no third-party BLE or
LAN dependencies. Generated Cupertino Icons dependencies were removed because
the screens do not need them. App lockfiles are retained.

Security work is isolated on `Security` in a separate worktree. Existing commits
are retained, including provenance for the imported background feature. Existing
local main/native/iOS branches and their files are not edited. iOS native verification
awaits Mac access. No history rewrite,
force-push or merge is part of this work. Publishing requires explicit authorization.
