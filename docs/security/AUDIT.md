# Targeted audit and applicability — 2026-10-04

Reviewed immutable main `a504c3fa26ab24a9218693fdfe9004cbe1aad758` and its import
`55f67d8` on Security, plus the subsequent security changes. Original main/native
local branches remain untouched. iOS `887bc13467a3aecebf3dc20792e190f022e72e5c`
is deferred; no iOS runtime or interoperability result is claimed.

## Implemented feature inventory

| Feature | Implementation evidence | Verification | Review now? |
| --- | --- | --- | --- |
| Flutter Android nearby discovery, request/approval, text chat | lib/main.dart, lib/relay_demo_controller.dart, lib/transport/ble_relay_transport.dart, Android BleRelaySession.kt | Source traced; fake-transport/channel/widget tests and native source compile pass. Security device matrix pending. | Yes |
| Android background helper and notifications | MainActivity.kt, ble/BleRelayForegroundService.kt, manifest non-exported service and notification permission | Imported existing committed feature. Native policy and Flutter snapshot tests pass; Android lifecycle/notification delivery not independently verified. | Yes |
| iOS native BLE on separate branch | origin/ios-mvp: ios/Runner code | Prior contributor validation records exist; not independently reproduced here. Main's iOS transport remains scaffold. | Deferred at user's request |
| Website/presentation | No website implementation in reviewed refs; no working web transport | No deployed site assessed | Deferred until committed implementation exists |
| Desktop networking, Internet relay service actions | Platform scaffolds and reserved envelope types/plans | No reachable implementation established | Deferred until implemented |
| Database, accounts/login, uploads | No implementation | Not applicable | No |

## Storage, logs and notifications

Inspected Flutter lib, local transport package and Android source. No product
chat/profile writes to files, preferences or databases were found. Chat history,
pending requests, display names and background backlog are process memory only.
Stopping/replacing the helper conversation clears retained request/backlog; app
history and draft cleanup are tested separately. This is logical cleanup, not
guaranteed overwriting of memory. Keyboard/system crash behavior is not assessed.

At a504c3f, BleRelaySession.kt 78-85 and 238-241 log discovery name/RSSI;
send/ACK calls log IDs and lengths, not normal chat content. Frame validation errors
use locally generated messages. BleRelayForegroundService.kt 238-240 and 271-274
logged parser exceptions. Their payload exposure is suspected until checked on a
device; the fix removes exception objects and retains constant warnings.

Service a504c3f 309-335 includes self-asserted names in notification text. OS
notification history and lock-screen visibility can retain/expose these names
according to device/user policy. No chat body is placed in notifications. Do not
claim notifications are private without device checks. Explicit immutable
PendingIntent (341-350) and non-exported service are existing protections.

AndroidManifest.xml a504c3f 9-12 does not explicitly set allowBackup or extraction
rules. Android's [Auto Backup documentation](https://developer.android.com/identity/data/autobackup)
describes backup being enabled by default and backing up eligible on-disk data.
No app-written chat data path exists to demonstrate a chat backup leak. Framework
preferences/caches, actual APK merged manifest and backup contents need owned-device
inspection. No blanket backup change or hypothetical database control was added.

## Local secret-pattern triage

Ran `python docs/security/check_history_secrets.py`: 225 unique text blobs reachable
from all locally available refs checked; 28 binary blobs skipped; no oversized blobs;
zero candidates for the script's five pattern families. Values are never printed,
and Git is read-only. No network scanner or upload is involved. A later rerun may
have larger counts because new audit/code commits become reachable.

This is limited triage, not proof that history contains no secrets. Unknown token
formats, encoded/binary secrets, ignored files, unreferenced objects and unfetched
remote history are outside coverage. No credential was found to revoke or remove,
and no Git history was purged. If a credential is found later, revoke it first;
any history rewrite would require separate authorization and collaboration planning.

## Dependency/advisory inspection

No dependency was added or upgraded by these security changes. Runtime direct
dependencies are Flutter SDK and the local relay_transport package. BLE uses native
Android APIs. pubspec.lock retains exact hosted versions and SHA-256 package hashes;
those hashes concern package integrity, not chat authentication.

Checked public primary advisory pages; only public product/package information
was queried. No source, credentials or user data was submitted.

| Component | Actual version evidence | Checked advisory and conclusion |
| --- | --- | --- |
| Temporary verification Flutter/Dart | flutter --version: 3.47.6 / 3.13.5 | [Dart Pub extraction advisory GHSA-q739-79rh-vmvp](https://github.com/dart-lang/sdk/security/advisories/GHSA-q739-79rh-vmvp) affects Dart before 3.11.0 / Flutter before 3.41.0. Verification SDK is outside these ranges. This does not inventory another developer's SDK. |
| Gradle wrapper | android/gradle/wrapper/gradle-wrapper.properties: gradle-9.3.1-all.zip | [GHSA-w78c-w6vf-rw82](https://github.com/gradle/gradle/security/advisories/GHSA-w78c-w6vf-rw82) and [GHSA-mqwm-5m85-gmcv](https://github.com/gradle/gradle/security/advisories/GHSA-mqwm-5m85-gmcv) patch the discussed repository-fallback defects at 9.3.0+. Declared wrapper is outside their affected ranges. |
| Hosted Dart packages | pubspec.lock (including development/test packages) | Compared package names against the 13 entries returned by the [GitHub Pub advisory listing](https://github.com/advisories?query=ecosystem%3Apub). No listed package matched this app lockfile. Listing/database/search coverage is incomplete; this is not a comprehensive vulnerability scan. |
| Android Gradle plugin / declared Kotlin plugin | android/settings.gradle.kts: 9.1.0 / 2.4.0 | No matching reliable advisory established. [JetBrains fixed-issues page](https://www.jetbrains.com/privacy-security/issues-fixed/) did not render usable details in this check. Full Gradle-resolved runtime dependency graph remains unverified because APK setup failed. |
| Native verification compiler | Cached Kotlin 2.1.20, Java 25 | Used only for local helper tests/source compilation; it is not evidence of the app's declared compiler or packaged standard-library version. |

No matched known-vulnerable dependency finding is asserted. A comprehensive resolved
dependency/advisory audit remains open; absence from these sources is not a guarantee.

## Requested checklist mapping

| Controls | Application here |
| --- | --- |
| 1 hide API keys; 2 purge Git secrets | No application API key identified; limited local history triage above. No purge/rewrite performed. |
| 3 public DB key; 4 row-level security; 7 record access; 13 parameterized queries | No database: deferred/inapplicable. |
| 5 encryption | Chat/link confidentiality and integrity policy remain open; device evidence required. No custom crypto added. |
| 6 server-side authentication | No server. Approval of the current peer conversation is the existing boundary; guards/test evidence in README. |
| 8 field tampering; 14 input validation | Strict envelope bounds/shape/version/types plus connection/request/state validation. Parsing is not cryptographic authentication. |
| 9 secure cookies; 10 password hashing; 11 login rate limits | No cookies/passwords/login. |
| 12 bot protection | No website bots; applicable nearby-peer resource controls: independent deadlines, bounded history/backlog and request-alert cooldown. Radio/CPU flooding still requires devices. |
| 15 escape user content | Flutter text/Android notification text, no HTML execution sink found. Website behavior deferred. |
| 16 uploads; 17 API response trimming | No uploads/server responses; advertising, logs and notification disclosure reviewed instead. |
| 18 headers; 19 HTTPS | No implemented HTTP website/transport. Deferred until real website code exists. |
| 20 dependency scanning | Version inventory and bounded primary-advisory review above; full graph audit open. |

## Smallest remaining checks

1. Owned Android phones: background request/accept/reject, idle setup expiry,
   disconnect A/reconnect B/return to UI, repeated alert behavior, stop availability,
   process restart. Record Android version/permission state and actual results.
2. Freshly unpaired owned phones: inspect BLE link encryption and authentication;
   bond status/ACKs alone are insufficient. Existing code has no explicit key exchange
   or requirement for encrypted/authenticated GATT permissions. No interception proven.
3. Synthetic malformed/chat/name markers: inspect logcat, app files/preferences/caches,
   lock screen, notification history and authorized backup contents. Never share raw
   private data or device identifiers.
4. Restore a working SDK/NDK build environment, build an APK with the declared
   toolchain, inventory its resolved dependencies/merged manifest and complete the
   advisory review. No success claimed for the previously failed build.
