# Implementation tracks

This comparison prevents the native Android application, Flutter host, and BLE experiment from being mistaken for one codebase. The changes on `feat/native-android-continuity` add the native app as a separate project. They do not modify the Flutter source or the experiment.

| Track | Location | Language/build | Purpose and status |
|---|---|---|---|
| Flutter host | `apps/offline_relay/` | Dart / Flutter | Cross-platform host scaffold. The `android/` subfolder is generated Flutter platform code and remains part of this host. |
| Native Android | `apps/offline_relay_android/` | Kotlin / Jetpack Compose / standalone Gradle | Android-only help-request and ephemeral-chat prototype using Google Nearby Connections. Build and JVM tests pass; complete physical two-phone flow still needs retesting on this branch. |
| BLE experiment | `experiments/ble_poc/` | Flutter/Dart UI plus isolated Android BLE code | Disposable central/peripheral investigation. It is not a dependency of either app. |
| Dart transport API | `packages/relay_transport/` | Dart | Transport-independent Dart interfaces. They are not imported by the Kotlin project and are not, by themselves, a wire protocol. |

## Separate boundaries

- Open `apps/offline_relay/` for Flutter work. Open `apps/offline_relay_android/` as its own Android Studio project for native work.
- Do not copy Kotlin files into `apps/offline_relay/android/`; that folder belongs to Flutter's generated Android host.
- The Kotlin project has its own Gradle settings, dependency catalog, application ID, source tree, permissions, UI, transport adapter, and tests. The Flutter project retains its own `pubspec.yaml`, Dart sources, and platform scaffolding.
- The native app uses Google Nearby Connections. The separate BLE experiment uses its own Android Bluetooth GATT implementation. They do not call one another.
- No cross-app message compatibility is claimed. The native app's JSON message codec is separate from the Dart interface and the experimental GATT protocol. Any future interoperability requires an agreed byte-level protocol and an explicit cross-client test.

## Scope and evidence

The repository's [`product V1 spec`](product/v1-spec.md) describes an engineering foundation and explicitly excludes a help/chat product. The native app branch is a separate prototype that goes beyond that baseline. It should remain isolated until the team agrees whether the V1 scope should change.

The native app demonstrates only one direct requester/helper pair. It has no server, accounts, persistence, order/payment integration, multi-hop relay, or identity verification. Local build and unit tests do not establish radio reliability. See [`apps/offline_relay_android/docs/BUILD-VERIFICATION.md`](../apps/offline_relay_android/docs/BUILD-VERIFICATION.md) and [`apps/offline_relay_android/docs/DEVICE-CHECK.md`](../apps/offline_relay_android/docs/DEVICE-CHECK.md).
