# iOS security work

## Committed baseline and provenance

The user authorized hardening existing committed iOS functionality on the single
Security branch. Imported only changed files under `apps/offline_relay/ios` and
the existing Swift native test entry point from immutable upstream commit
`57d8348fd4f3a7b29742925aed7804370ff993fe` (including its existing background and
notification implementation). Shared Dart/Android hardening is retained; upstream
Dart, Android, UI and unrelated branch files are not imported. This is a selective
source import, not a merge, cherry-pick or claim that this combined app was already
validated by the contributor. Original commit authorship/history remains intact;
the new import commit records the actual security-work author/time and provenance.

Windows has no Swift compiler on PATH or Xcode. Native tests and iOS build/device
checks must be recorded as NOT RUN until performed with suitable tooling. Existing
contributor assertions and physical-device records are not this review's results.

## Applicable existing functionality

CoreBluetooth discovery/duplex framing, foreground peer chat, app-owned background
helper availability, local request notifications and availability restoration exist
in source. Background runtime guarantees require devices. Helper enabled/profile
values are persisted in UserDefaults; chat, request and connection state is in
memory. No website, database or Internet relay action is introduced.

## Findings in upstream 57d8348

All evidence below refers to `apps/offline_relay/ios/Runner` at the immutable
baseline above. A nearby attacker must establish the existing BLE helper link;
the attacker cannot directly inject Flutter method-channel events.

| Finding | Evidence and reachable path | Existing protection / impact | Severity and confidence | Minimal prepared fix and validation |
| --- | --- | --- | --- | --- |
| I1: Request replacement changes native consent state | BleHelperAvailability.swift 125-136 delivers received bytes to BleHelperState.swift 26-37; a second valid request overwrites request/name and resets accepted | 256-byte request limit, JSON/version checks and current radio session exist. Shared Security controller retains its first request; native replacement can desynchronize the prompt/decision or invalidate an accepted replay | Medium; high confidence in source behavior, physical timing unverified | Validate role/name and retain the first request until connection teardown; resolve only once. Swift tests send 20,000 replacements, wrong decisions and postapproval requests; NOT RUN here |
| I2: Native background queue accepts unapproved chat | BleHelperState.swift 38-41 queues chat when listener is detached, independently of accepted state | Already capped at 32 messages; transport caps messages at 256 bytes. Upstream Dart had no approval gate; Security shared Dart already gates delivery. Unapproved data can occupy native replay state, which should contain only approved chat | Low on combined Security; medium in upstream combination; high source confidence, UI impact requires device check | Admit/forward only approved chat with valid envelope/text, keep existing 32-message cap. Native preapproval/oversize/burst/reset tests prepared; NOT RUN |
| I3: Detached disconnect has no authoritative replay snapshot; accepted replay loses its request | BleHelperAvailability.swift 34-47 emits live state only; empty state returns before replay. BleHelperState.swift 54-59 removes request before retaining accepted event | Session generation guards and native teardown exist. Flutter misses disconnect events while detached; its previously known connection can survive. Security approval checks also need a retained matching request to restore a valid live chat | Medium; source contract mismatch confirmed; actual iOS lifecycle ordering unverified | Emit current/empty helper snapshots, retain approved request, clear on teardown, and guard send completion by session/generation. Two new shared bridge tests passed; existing four snapshot tests passed. Native replay and device checks pending |
| I4: Changed request IDs/reconnects bypass notification deduplication; detached idle link has no initial-request timeout | BleHelperState.swift 83-89 deduplicates IDs only; BleHelperAvailability.swift 125-129 has no initial request deadline | Seen IDs bounded at 256; async alert tokens, authorization/foreground checks and radio operation deadlines exist. Valid new IDs can repeatedly alert; subscribing without a request occupies the single helper slot while Dart is detached | Low-Medium; source policy gap high confidence, device rate/OS scheduling unknown | Keep a 10-second monotonic alert cooldown across reconnects and a session-guarded 15-second initial request deadline. Suppression keeps request in UI; valid request cancels setup timeout. Swift cooldown tests prepared; timeout/background/re-advertising require devices |

Peer names remain self-asserted. These fixes do not authenticate a person's identity
or add encryption. Bluetooth link protection remains unverified. No database,
cryptography package or additional persistence is added. Existing availability and
profile preferences are retained; their backup/privacy behavior still needs devices.

## Actual verification and commit boundary

- The selected baseline import is committed as 32905c0. Its iOS source matches
  the recorded upstream commit; no upstream shared Dart or Android source is adopted.
- `flutter test --reporter compact`: PASS, all 38 tests, including two new
  idle/empty iOS snapshot bridge checks. These check the real shared Dart channels
  with simulated events; they do not execute Swift or CoreBluetooth. No claim that
  these two tests failed before the native fix: existing Security bridge already
  handles the contract and the new native implementation must produce it.
- `flutter analyze`: PASS, no issues. `git diff --check`: PASS.
- `where.exe swift`: no compiler found. No installed WSL or Swift toolchain found
  in checked locations. Swift native tests, Xcode build and iPhone tests: NOT RUN.
- The user has access to a Mac later. Native fix/test files are deliberately left
  uncommitted on Security until compilation and native verification, following the
  user's requirement to commit verified fixes. Shared bridge tests and this audit
  may be committed independently. No iOS app build or security completion claimed.

Prepared native files: BleHelperState.swift, BleHelperAvailability.swift and
`apps/offline_relay/test/native/main.swift`. A local transfer patch contains only
these pending changes; it is not an applied fix on main or ios-mvp.

## Mac verification procedure (NOT RUN)

Use a clean Security checkout at the recorded documentation commit. Transfer the
local native review patch and inspect it before `git apply --check` / `git apply`.
Patch SHA-256:
`2a40637ad335ba38888f8eebb603f3bd0c4a0d72c02ea0d149bb73b23a76de15`.
Its filename is `Offline-relay-ios-security-review.patch`; it was saved locally
in TEMP, not committed or uploaded. `git apply --reverse --check` passed against
the pending worktree changes; this was a read-only consistency check, not an undo.
Run from `apps/offline_relay` with Xcode's Swift toolchain:

```sh
ios_security_test_dir=$(mktemp -d)
swiftc ios/Runner/BleFraming.swift ios/Runner/BleMessageReceiver.swift \
  ios/Runner/BleProfile.swift ios/Runner/BleHelperState.swift \
  test/native/main.swift -o "$ios_security_test_dir/ios-security-tests"
"$ios_security_test_dir/ios-security-tests"
flutter analyze
flutter test
flutter build ios --debug --no-codesign
```

Record tool versions, source/patch hashes, commands, failures and actual outcomes.
Foundation policy tests do not compile UIKit/CoreBluetooth integration; the full
iOS build is a separate required check. Do not commit native fixes as verified
until both succeed. Signed installation and phone testing remain deferred.

On controlled phones later, verify first-request stability against replacements,
preapproval chat drops, normal accept/reject and same-live-session replay; disconnect
A while detached then connect B and ensure no A approval/history returns. Verify
that clear snapshots preserve an ordinary Offline User launch, helper advertising
resumes after close/reject/timeout, disabling availability prevents restart, and a
valid initial request does not time out while a person decides. Repeat alert IDs
and reconnect within/after ten seconds; permission denial, foreground suppression,
late scheduling completions and process restart must preserve correct request state.
Background suspension can delay deadlines; no wall-clock execution guarantee is
made. Check synthetic chat/name data in logs/preferences/backups and actual radio
encryption/authentication separately; no unrelated devices or services may be probed.
