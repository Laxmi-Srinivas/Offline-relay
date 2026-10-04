# Latest upstream review and verification update

## Reviewed snapshots

`git fetch origin` and read-only log/diff/show checks found:

| Ref | Immutable commit | Source changes | Verification status |
| --- | --- | --- | --- |
| origin/main | 67acd0632eb1965482d7b745e06f1ef0c83b55f5 | Flutter mobile UI, bundled fonts, discovery timeout and error handling | Source reviewed; not imported or tested on Security |
| origin/ios-mvp | 57d8348fd4f3a7b29742925aed7804370ff993fe | iOS background availability and validated request notifications, following 692ff01 | Source reviewed; iOS implementation and device verification deferred |
| Security | 8f2621c75fe31239d15062be2b663e8ee64fdca1 | Existing Android hardening and background implementation | Previously recorded automated checks; successful debug APK build below |

These are fetched snapshots, not a guarantee about later pushes or unpublished
work on another contributor's computer. No newly pushed Android security audit
or transport-hardening commit was found on main. Its latest change does not touch
Android native transport, transport libraries or security documentation. The
12-second discovery timeout limits scan duration; it is not message authentication.
The new screens are Flutter mobile UI, not a website implementation.

## Overlap and remaining gaps

On main at the recorded commit, `apps/offline_relay/lib/relay_demo_controller.dart`
lines 342-357 still accept a helper approval without matching the current
connection/request; lines 392-396 still allow replacement of a pending request;
lines 411-421 still append received chat without an approval gate, history bound
or recent-ID suppression. These are existing findings covered by Security's
regressions, not newly introduced regressions or removal of Security changes.
Security and main have diverged; Security test results do not cover the new UI.
Before any future integration, compare implementations and rerun consent,
session cleanup, draft, bridge and bounded-memory regressions on the agreed base.
Do not merge or import this UI merely to complete a security review.

iOS now has generation guards and notification authorization/current-request
checks. Its helper state bounds unread messages to 32 and notification seen IDs
to 256. It also persists availability/profile in UserDefaults; this is identifier
and display-name persistence, not chat persistence. Review profile retention and
backup expectations before making a privacy claim. Stable pending requests,
approval correlation and physical background/notification ordering still need
targeted checks on an authorized iOS workstream. Contributor test records are not
tests run by this security review. No iOS fixes are adopted here.

## Successful Android build

This supersedes the earlier unresolved build limitation, while preserving its
failure record. Source commit: `8f2621c75fe31239d15062be2b663e8ee64fdca1`.
Flutter 3.47.6 / Dart 3.13.5; declared Gradle pipeline, debug variant.

- Installed official NDK 28.2.13676358 after the initial SDK setup failure.
- A subsequent build failed because disk space was exhausted. The user freed
  space; no user files were deleted by this work.
- `flutter build apk --debug` then passed. No phone installation was performed.
- Output: `apps/offline_relay/build/app/outputs/flutter-apk/app-debug.apk`.
  Size: 154991666 bytes. SHA-256:
  `3BC2F43EE8497D94F0B7B43E5A11F0C8B1D4212C0F81C8A082231A4C7851F9E7`.
- `apksigner verify --verbose` passed; APK signature scheme v2 verified. This is
  a debug-signed test artifact, not production signing or transport encryption.
- `:app:dependencies --configuration debugRuntimeClasspath --offline --console=plain`
  passed. Exact output is in `android-debug-dependencies.txt`. No build scan was
  enabled and no source was sent to an external scanner. Debug dependency
  resolution is established; release resolution and comprehensive advisory
  coverage are not. No matching new vulnerability was established by this step.

The packaged debug manifest was inspected: minimum API 31, target API 36,
debuggable, non-exported helper service. Debug INTERNET permission supports Flutter
debugging; it does not establish an implemented website. Device checks for
Bluetooth encryption/authentication, notifications, lifecycle, logs and backups
remain pending. Existing automated counts remain 36 Flutter and 15 native policy
tests; no tests were rerun or claimed for the new upstream commits.

## Collaboration record

Security was published at 8f2621c under the user's explicit push authorization.
The original checkout remains on feat/native-android-continuity at cbb1ed6;
local main remains 6128998. Fetch updated remote-tracking refs only. No other
local branch was edited, no merge or history rewrite was performed, and no APK
binary is committed. Phone testing is paused at the user's request; the prepared
two-phone procedure is in PHONE_TESTING.md.
