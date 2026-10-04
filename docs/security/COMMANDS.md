# Command and outcome record

Commands run only in the Security worktree unless stated otherwise. Test-generated
files and temporary tooling are not application persistence. Git commits use the
existing configured author and actual timestamps; no pushes are authorized.

| Command / operation | Purpose | Actual outcome and limitation |
| --- | --- | --- |
| Read-only git status, refs, tree/show/diff/grep | Establish source baseline and inspect reachable flows | Main e402922d80f9830bce08a752dc8a1e05a895bd30; iOS 887bc13467a3aecebf3dc20792e190f022e72e5c. Original native checkout clean. No builds/tests during review. |
| `git fetch origin` (before implementation, explicitly authorized) | Obtain missing/new remote snapshots | Main advanced; iOS ref appeared. Local branches/files unchanged. |
| `git worktree add -b Security C:/Users/mamid/AppData/Local/Temp/Offline-relay-Security e402922d80f9830bce08a752dc8a1e05a895bd30` | Isolate authorized edits | Succeeded. Original checkout remained on feat/native-android-continuity. |
| Tool lookup and SDK/cache file discovery | Find local test tools | Java and cached Kotlin compiler found; Flutter/Dart absent from PATH. One unrelated temporary directory was unreadable. |
| Official Flutter release manifest via Invoke-RestMethod, then approved unrestricted retry | Obtain matching SDK information | Both failed with NoSuchKey; no repository data submitted. |
| `git clone --depth 1 --branch 3.47.6 https://github.com/flutter/flutter.git C:/Users/mamid/AppData/Local/Temp/Offline-relay-security-flutter` | Obtain official temporary test SDK | Clone obtained framework 5fc346839b5d0eef006ed8404392afb4dfae428d; checkout reported one overlong engine-test asset filename. SDK bootstrap verification pending. No product branches touched. |

Further results will be appended after execution, not predicted.

### Consent and session isolation

- Temporary `flutter.bat --version` bootstrapped successfully: Flutter 3.47.6,
  Dart 3.13.5. The overlong SDK engine-test asset did not prevent these checks.
- From `apps/offline_relay`, `flutter pub get` passed with the committed dependency
  versions. It reported newer incompatible versions; no dependency upgrade was made.
- Before controller fixes, `flutter test test/security_controller_test.dart
  --reporter expanded` failed all 10 tests, reproducing consent and session defects.
- After fixes, the same command passed all 10 tests.
- `dart format lib/relay_demo_controller.dart test/security_controller_test.dart`
  completed. Initial `flutter analyze` found one missing-braces lint; it was fixed.
- `flutter analyze` then passed with no issues. `flutter test --reporter expanded`
  passed all 19 tests (9 existing + 10 security regressions).
- Pub tooling rewrote generated desktop registrant line endings. Those generated
  files were restored to the Security HEAD version; no desktop functionality was changed.
- These tests use local fake transports; no radios, unrelated devices or services
  were probed. Device acceptance/reconnect verification remains pending.

### Independent deadlines and idle setup

- Added production `BleDeadlines` helper and used it in Android session: separate
  setup/send/receive cancellation, plus a notification-subscription deadline.
- Added controller request-setup timer and two tests using Flutter controlled time.
  First attempt constructed subscriptions outside the fake-time zone, causing one
  test failure; test setup was corrected. Both timer tests then passed.
- `flutter analyze` passed; the complete Flutter suite passed all 21 tests.
- `apps/offline_relay/test/native/run_deadline_tests.ps1` compiled the production
  helper and tests with cached Kotlin 2.1.20 and Java 25; all 6 tests passed. Java
  printed an Unsafe deprecation warning from the compiler, not an app test failure.
- Started `flutter build apk --debug` with process-local ANDROID_SDK_ROOT pointing
  to the existing Android SDK. It downloaded official Flutter Android artifacts and
  Gradle dependencies. FAILED before app compilation because SDK Manager could not
  install NDK 28.2.13676358. No APK result is claimed. Tooling emitted Android CLI
  usage-metrics information during its automatic setup; no source scan was requested.
- Downloaded the matching debug Flutter embedding JAR from the official Flutter
  Maven host to TEMP (engine b8c8d3d8d5d0095127057f8a29ca8cc53da2167c).
- Ran `run_deadline_tests.ps1 -AndroidJar <installed android-35/android.jar>
  -FlutterEmbeddingJar <TEMP/flutter_embedding_debug.jar>`: 6 tests passed again,
  and the actual `BleRelaySession.kt` plus helper compiled successfully against
  Android API 35 and the matching embedding. This uses Kotlin 2.1.20, not the full
  declared Gradle/AGP pipeline; it establishes source compilation only.
- The first verified commit is `3ec8369` (consent and conversation lifecycle).

### Bounded conversation memory and duplicate display

- Deadline/setup work committed as `2b30aac` on Security only.
- Added 5 memory/duplicate tests before implementing the policy. Four failed on
  the unchanged behavior (duplicates, incoming/local bounds and recent-window
  suppression); the conversation-reset test already passed.
- Selected newest 300 messages and newest 1024 incoming IDs per conversation after
  the user requested advice. Added a visible history-limit notice; no persistent
  storage and no web presentation implementation were added.
- An analysis lint preferred a set literal instead of an explicit LinkedHashSet
  constructor; changed to Dart's insertion-ordered set literal.
- `flutter analyze` passed with no issues; all 26 Flutter tests passed, including
  17 security regressions. Previous 6 native timer tests/source compilation remain
  applicable because native source did not change in this step.
