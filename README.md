# OfflineRelay engineering foundation

This repository contains a minimal Flutter host, a pure Dart transport boundary,
design documentation, and a disposable Android BLE experiment. It is not the
OfflineRelay product. No accounts, backend, service requests, chat UI, or LAN
implementation are included.

## Layout

- `apps/offline_relay/`: placeholder host with Android, iOS, Linux, macOS, and
  Windows scaffolds. These are intended targets, not verified runnable builds.
- `packages/relay_transport/`: transport-independent discovery/connection/message
  interfaces; no production adapters.
- `experiments/ble_poc/`: separate Android 12+ central/peripheral experiment.
  The product host has no dependency on it.
- `docs/`: [scope](docs/product/v1-spec.md),
  [architecture](docs/architecture/overview.md),
  [transport constraints](docs/architecture/transports.md),
  [ADR](docs/decisions/ADR-001-transport-architecture.md),
  [protocol](docs/protocols/message-protocol.md), and
  [device evidence](docs/testing/device-matrix.md).

## Toolchain and commands

Generated with Flutter **3.47.6**, Dart **3.13.5**, framework revision
`5fc346839b`. A temporary SDK was obtained from the official Flutter stable
repository at `/tmp/offlinerelay-flutter-sdk`; it is not part of the repository
or a persistent installation. Put a matching Flutter SDK on PATH to use the
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
Native build verification and physical-device testing remain outstanding; see
the [validation record](docs/testing/validation.md). No platform is currently
claimed as a verified runnable BLE POC.

## Dependencies and Git

Both apps use Flutter, Flutter's test SDK, and `flutter_lints` 6.x. The host also
references the local `relay_transport` package. There are no third-party BLE or
LAN dependencies. Generated Cupertino Icons dependencies were removed because
the placeholder/diagnostic screens do not need them. App lockfiles are retained.

Initial checkout: empty, uncommitted `main`; origin
`git@github.com:Laxmi-Srinivas/Offline-relay.git`. The original repository was
preserved. No commits or pushes were made.
