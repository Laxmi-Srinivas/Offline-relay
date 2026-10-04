# OfflineRelay for native Android

This is the independent **Kotlin + Jetpack Compose** Android implementation. It lives beside `apps/offline_relay/`, the Flutter host; it does not replace or share build files with it. The generated `apps/offline_relay/android/` directory remains owned by the Flutter project.

## What this Android prototype does

- Connects two nearby Android phones directly with Google Nearby Connections.
- Lets one phone act as the requester and one as the helper.
- Verifies the phone connection, then exchanges a bounded help request, accept/decline response, and temporary chat.
- Keeps help and chat data in memory for the session. It does not use a server, account, database, ordering, or payment flow.

This branch is a separate Android prototype beyond the current repository V1 engineering foundation. It is **not interoperable** with the Flutter app or `packages/relay_transport`; the Android message codec and Flutter/Dart transport interface are separate. See [`docs/implementation-tracks.md`](../../docs/implementation-tracks.md) for the comparison and [`docs/DEMO.md`](docs/DEMO.md) for judge framing.

## Open and build

Open the `apps/offline_relay_android/` folder itself in Android Studio. Use JDK 17 and Android SDK Platform 35. In Android Studio, wait for Gradle sync, select the `app` configuration, connect an Android phone, enable USB debugging, and press **Run**.

From PowerShell in this folder:

```powershell
java -version
.\gradlew.bat --version
.\gradlew.bat :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
```

The first command checks the Java runtime; the wrapper command reports the pinned Gradle/JVM versions; the last command builds the app, runs the local JVM tests, and checks Android lint. These checks do **not** prove Nearby connections work on a phone.

## Device test status

The local build and JVM tests pass: 42 tests, zero failures. Lint succeeds with 13 warnings and no errors. The complete two-phone help/chat flow has not been re-tested on this packaged branch. Follow [`docs/DEVICE-CHECK.md`](docs/DEVICE-CHECK.md) and update [`docs/BUILD-VERIFICATION.md`](docs/BUILD-VERIFICATION.md) with results from the same build before calling the live demo verified.

## Files

- `app/`: Kotlin/Compose application source and tests.
- `gradle/`, `gradlew`, `gradlew.bat`: this app's independent Gradle wrapper and dependency catalog.
- `docs/`: protocol, architecture, privacy boundaries, demo, and test evidence.
