# onya

Nearby, voluntary peer-to-peer text chat over Bluetooth Low Energy. A helper
chooses to be available, a requester discovers them, and the helper accepts or
rejects. Messages travel directly between phones without a central chat server.
Both people must install the app before going offline.

**Hackathon scope: Android ? Android and iPhone ? iPhone only.** Android ? iPhone
communication is excluded. The repository retains its historical OfflineRelay
name and technical identifiers.

## The two mobile builds

| | Android | iPhone |
| --- | --- | --- |
| Application | `apps/offline_relay` | `apps/offline_relay_ios` |
| Native adapter | Kotlin, Android GATT | Swift, CoreBluetooth central/peripheral |
| Protocol package | `packages/relay_transport` | `packages/relay_transport_ios` |
| Chat protection | Automatic X25519 / HKDF / AES-GCM | Plaintext application envelopes; Bluetooth link protection unverified |
| End chat | End Chat button and encrypted end message | Chat back button closes BLE and returns to Nearby |
| Report | Local, in-memory only | Absent from the preserved iOS baseline |
| Helper availability | Foreground service and request notifications | CoreBluetooth background helper and local notifications |

The validated platform applications used different controllers and protocol
versions. Separate Flutter build targets preserve those implementations without
rewriting either networking stack. Both use bounded JSON envelopes, 256-byte
messages, fragmentation/reassembly and transport ACKs. Matching technical UUIDs
are not a claim of protocol compatibility. The native Android rewrite is excluded.

Android encryption does not authenticate peer identity or prevent active
impersonation. Use non-sensitive text for the iPhone demo. This is a hackathon
prototype, not a production-secure messenger.

## How it works

Profile ? Help Others / Find nearby ? discovery ? BLE connection ? request ?
explicit acceptance ? bidirectional text chat ? end/disconnect. Android also
establishes fresh encryption keys automatically after acceptance, with no manual
code verification. A new connection starts a new session. Neither platform
provides Internet access, automatic reconnect or central moderation.

## Android setup

Reference: Flutter 3.47.6 / Dart 3.13.5, Android SDK and a compatible JDK.
Phones require Android 12+ (API 31); helper hardware must support advertising.

```sh
cd apps/offline_relay
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
adb devices -l
adb -s DEVICE_SERIAL install -r build/app/outputs/flutter-apk/app-debug.apk
flutter run -d DEVICE_SERIAL
```

Grant Nearby Devices and helper notification access; enable Bluetooth. The app
ID remains `dev.offlinerelay.offline_relay`. Debug APKs use debug signing and are
demo artifacts, not production releases.

## iPhone setup (Mac required)

Use the same Flutter version, Xcode with the iOS SDK and two physical iPhones
(deployment target iOS 15+). Build the **iOS target below**, not the unused iOS
scaffold inside the Android application.

```sh
cd apps/offline_relay_ios
flutter pub get
flutter analyze
flutter test
flutter build ios --debug --no-codesign
open ios/Runner.xcworkspace
flutter devices
flutter run -d IPHONE_DEVICE_ID
```

Choose a local signing team in Xcode, trust the development profile/enable
Developer Mode when required, and install on both iPhones. Keep signing settings
local. The bundle ID remains `dev.offlinerelay.offlineRelay`. Grant Bluetooth
and helper notification access. Windows-side Flutter tests do not compile Swift.

Foundation-only native fixtures on the Mac, from the iOS app directory:

```sh
xcrun swiftc ios/Runner/BleFraming.swift ios/Runner/BleMessageReceiver.swift \
  ios/Runner/BleProfile.swift ios/Runner/BleHelperState.swift \
  test/native/main.swift -o /tmp/onya-ios-tests
/tmp/onya-ios-tests
```

## Website and distribution

The static site is in `website/onya`, with no npm dependencies, backend, tracking
or external resource loading.

```sh
python website/onya/preview.py
python website/onya/tests/static_check.py
python website/onya/package_site.py --output dist/onya-site.zip
```

Preview at the local address printed by the script. Deploy only the packaged
contents. [Deployment instructions](website/onya/DEPLOYMENT.md) cover GitHub
Pages and app hosting. The prepared Pages workflow publishes reviewed website
changes from main; this integration branch does not deploy anything.

Android: publish the verified APK as a GitHub Release asset, then fill its real
URL, version and source commit in `website/onya/release-config.js`. No public APK
was available when integration began. iOS: configure a real TestFlight/App Store
URL when available. Until then, public distribution is marked pending and the
website explains developer installation. An arbitrary IPA is not an install route.

## Simplest live demo

Use **two phones of the same platform**, running the same platform build.

1. Open onya on both phones; enter different names in Profile.
2. On B, enable Help Others. On A, choose Find Users Nearby.
3. A selects B and requests a connection; B accepts.
4. On Android, wait for automatic secure setup. Send two short messages A ? B
   and two B ? A. Confirm display on both phones.
5. End chat: Android **End**; iPhone **back arrow**. Confirm peer disconnection.
6. Start a fresh session, reverse requester/helper roles and repeat.
7. Close/reopen the apps and start a new connection. Demonstrate background helper
   notifications only after checking them on the actual demo devices.

Keep messages short to fit the complete 256-byte envelope and requesters in the
foreground. Process death/force-stop can end sessions; background scheduling
depends on the OS. There is no automatic reconnection guarantee.

## Verification and provenance

[Final integration record](docs/testing/final-integration.md) distinguishes
checks performed here from prior team-reported device results and remaining Mac
work. See [architecture](docs/architecture/overview.md),
[Android encryption](docs/security/e2e-chat.md) and
[iPhone baseline validation](docs/testing/ios-phase-one-ui.md).
Historical records retain their original scope; the integration record is
authoritative for this submission.

`experiments/ble_poc` stays frozen. The abandoned interop branch is preserved in
Git but excluded from this integration. `feat/native-android-continuity` is also
excluded. Never commit APKs, build output, device logs or signing credentials.
