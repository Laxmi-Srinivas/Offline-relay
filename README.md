# OfflineRelay engineering foundation

This repository is organized into distinct implementation tracks. The default `main` branch is the Flutter and transport-engineering foundation. The `feat/native-android-continuity` branch adds a separate Kotlin/Compose Android help-and-chat prototype for evaluation; it does not replace the Flutter host or the BLE experiment.

## Implementation tracks

- [`apps/offline_relay/`](apps/offline_relay/): Flutter/Dart host scaffold with generated Android, iOS, Linux, macOS, and Windows platform folders. These are intended targets, not all verified runnable builds.
- [`apps/offline_relay_android/`](apps/offline_relay_android/): standalone native Android project using Kotlin, Jetpack Compose, and Google Nearby Connections. Open this folder itself in Android Studio. This branch has a working two-role help-request/chat flow in code; local build and JVM tests pass, but the full physical two-phone flow needs fresh verification.
- [`experiments/ble_poc/`](experiments/ble_poc/): disposable BLE central/peripheral experiment, separate from both app implementations.
- [`packages/relay_transport/`](packages/relay_transport/): transport-independent Dart interfaces. The Kotlin app does not import this package.
- [`docs/`](docs/): original product scope, architecture, protocol, and transport evidence. The native branch goes beyond the original V1 scope and remains isolated until the team decides whether to adopt that change.

Read [`docs/implementation-tracks.md`](docs/implementation-tracks.md) before changing project structure. The Flutter-generated `apps/offline_relay/android/` files belong to the Flutter app; keep the Kotlin source and Gradle files in `apps/offline_relay_android/`. The apps do not share implementation code or claim cross-client wire compatibility.

## Flutter toolchain

The Flutter host was generated with Flutter **3.47.6** and Dart **3.13.5**. Open `apps/offline_relay/` in Flutter tooling. Run the following in that folder:

```sh
flutter pub get
flutter analyze
flutter test
flutter build bundle --debug
```

The bundle command compiles Flutter assets/Dart only; it does **not** validate native platform code or produce an installable app. Run `dart analyze packages/relay_transport` from the repository root. Platform build and device prerequisites vary.

## Native Android toolchain

Open `apps/offline_relay_android/` as an independent Android Studio project with JDK 17 and Android SDK Platform 35. From PowerShell in that folder, run:

```powershell
.\gradlew.bat :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
```

This builds the app, runs local JVM tests, and runs lint. It does not substitute for the physical-device checklist linked from that project's README.

## Repository intent

The Flutter and native Android apps are separate implementations in one repository. Keep feature work on focused branches and preserve the boundaries above. Update shared scope/protocol docs only after agreement; do not call the Dart transport interfaces a shared protocol. The BLE experiment remains disposable and independent.
