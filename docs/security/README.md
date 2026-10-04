# Security work record

Work is confined to branch `Security`, based on committed Android Flutter source
`e402922d80f9830bce08a752dc8a1e05a895bd30` (local `origin/main` at review time).
The separate worktree preserves the original native-Android checkout. Existing
branches must not be modified, merged, rewritten, or pushed by this work.
iOS at `887bc13467a3aecebf3dc20792e190f022e72e5c` was inventoried, not adopted
as the implementation base. Website, desktop transports, Internet relay actions
and persistence are absent or incomplete and deferred. No database is introduced.
Committed Android background availability from
`a504c3fa26ab24a9218693fdfe9004cbe1aad758` was imported on Security with
`git cherry-pick -x` as `55f67d8`, retaining original authorship/provenance.
The rejection conflict was reconciled to retain session cleanup and ongoing help.
Existing Security commits remain ancestors; no branch merge or history rewrite.

## Existing architecture and trust boundaries

Android 12+ app: Flutter Nearby/Chat UI -> RelayDemoController -> BleRelayTransport
method/event channels -> MainActivity -> BleRelaySession -> GATT. For Help Others,
a non-exported BleRelayForegroundService owns the peripheral connection while the
Activity is detached, shows ongoing/request notifications, and returns a current
connection/request/approval snapshot when the UI returns. Notification PendingIntent
is explicit and immutable. Notifications do not accept a request; approval remains
an app action. Background queues hold only bounded, approved current-session chat.
Central writes DATA and reads ACK; peripheral sends DATA notifications and receives
ACK writes. Messages use UTF-8 JSON envelopes, at most 256 bytes including all
fields, fragmented into frames of at most 20 bytes (16 payload bytes).
Service/characteristic UUIDs select a protocol, not an authenticated person.
Names and roles are self-asserted. Offering help does not prove Internet access.
The helper's approval is an application boundary distinct from a BLE connection.
Reserved service-request/response messages are not implemented actions.

## Data and assumptions

Chat and profiles are in memory; no application file/preferences/database write
path was found. Android logs diagnostic names/RSSI and IDs/lengths, not product
chat text in normal diagnostic calls. Background envelope parse failures previously
logged exception objects that may include input; these now log a constant warning.
A short name/role is public in advertising and peer names appear in notifications.
OS logs, crash reports, keyboard caches, backup contents and actual radio security
require device verification. No secure erasure or private-chat guarantee is made.
All test input must be synthetic; testing is limited to authorized local code and
devices. No source or user data is sent to a scanner. Official SDK/package hosts
may be contacted to acquire tooling; that is not an external code scan.

## Review evidence

Evidence locations below refer to the immutable base commit, not later line
numbers. Controller path: `apps/offline_relay/lib/relay_demo_controller.dart`.
Native path: `apps/offline_relay/android/app/src/main/kotlin/dev/offlinerelay/offline_relay/ble/BleRelaySession.kt`.

| ID | Finding and evidence at base | Prerequisite, impact, existing protection | Severity / confidence | Status |
| --- | --- | --- | --- | --- |
| S1 | Accept/reject lacks state/connection guard; missing requestId matches null; chat unconditionally appended. Controller 220-229, 254-297. | Connected unapproved peer changes UI to chat or inserts messages. Normal approval UI and outer JSON validation exist. Does not prove disclosure. | Medium / high source confidence | Fixed: current-connection/pending-request checks and accepted-chat gate; automated regressions passed; device check pending |
| S2 | Shared timer replaced/cleared by receive. Native 96-105, 190-212, 446-471, 573-605. | Connected peer sends inbound traffic while withholding send ACK; outstanding send may never time out. Existing cap and nominal 15-second deadline do not isolate operations. | Medium / high source confidence | Fixed with independent setup/send/receive deadlines; 6 production-helper tests pass; device verification pending |
| S3 | Idle peer occupies one slot; no request setup expiry. Native 399-440; controller 220-231. | Nearby peer connects without subscribing or requesting. Blocks other peers. Foreground teardown and one-peer restriction exist. | Medium / high source confidence | Subscription and request setup each expire after 15 seconds; controller/helper tests and native source compilation pass; full APK/device verification pending. Valid requests keep existing human accept/reject behavior. |
| S4 | Disconnect retains controller history/references. Controller 107-116, 197-218, 234-251. | Peer disconnect/error followed by another chat; old history can appear under new peer or reconnect is blocked. Explicit back action and native cleanup exist. History is not transmitted automatically. | Medium / high source confidence | Fixed: common cleanup and stale async completion guards; automated disconnect/reconnect regressions passed; device check pending |
| S5 | Unbounded history; repeated envelope IDs appended. Controller 30-31, 179-195, 287-297. | Connected peer repeats valid messages; duplicate display and increasing memory. 256-byte per-message cap exists. Practical exhaustion rate unknown. | Low-Medium / high for growth, medium for exhaustion | History now retains newest 300 messages; duplicate suppression uses newest 1024 incoming IDs per conversation. Automated boundary tests pass; radio flooding remains unverified. |
| S6 | No required encrypted/authenticated link or application key exchange. Native 121-138, 176-187, 190-212, 551-570; envelope encode in packages/relay_transport/lib/relay_transport.dart 126-142. | Radio attacker would need an unprotected link and suitable capability; interception not demonstrated. User selection and IDs/ACK checks are not cryptographic authentication. | Medium / high for missing policy, actual link state unknown | Device security inspection and pairing UX agreement required; no crypto implemented |

The controller on the reviewed iOS branch is identical and shares S1/S4/S5;
native iOS remediation remains deferred. Android and iOS branches diverge in
their native adapters; no interoperability or merge is implied.

## Background review (immutable source a504c3f on origin/main)

Service path below: `apps/offline_relay/android/app/src/main/kotlin/dev/offlinerelay/offline_relay/ble/BleRelayForegroundService.kt`.
Activity path: `apps/offline_relay/android/app/src/main/kotlin/dev/offlinerelay/offline_relay/MainActivity.kt`.

| ID | Original evidence | Attacker/path, protection and impact | Severity/confidence | Remediation and validation |
| --- | --- | --- | --- | --- |
| S7 | Service 41-42, 180-241, 283-286; Activity 33, 58-65 | Connected nearby peer sends bounded frames while helper UI detached. Every event was queued and unique request IDs retained indefinitely; per-message 256-byte cap, one-peer limit, non-exported service exist. Aggregate memory grows; practical exhaustion rate unknown. | Medium / confirmed source growth | Keep one request per connection; queue only accepted chat, newest 300/76,800 payload bytes; Activity event buffer bounded too. Nine native policy/buffer tests pass, including 20,000-message bursts. OS/radio exhaustion not demonstrated. |
| S8 | Service 69-91, 180-220; controller 285-299; bridge 133-144 | A native approval queued for ended A may be replayed after snapshot B. Peer cannot forge method-channel events directly. Controller ignored connection/request identity; delayed approvals can change chat state. Actual Activity timing remains unverified. | Medium / confirmed controller defect, device sequence pending | Native snapshots replace queued historical controls, session/send completion guards, bridge prunes ended helper connections, controller requires current connection object and request ID. Three new negative regressions failed before fix; positive restore passed. All four pass afterward; four bridge ordering/reconnect tests pass. |
| S9 | Service 222-241, 325-335 | Connected peer repeatedly changes request ID; service replaces pending name/request and raises new alerts. One-slot connection, fixed notification ID and user permission exist. Alert churn and unstable consent prompt; identity claims themselves are not defects. | Low-Medium / high source confidence | First valid request remains stable; one alert per connection and monotonic 10-second cooldown across reconnects within service lifetime. Suppressed alerts do not discard requests. Native stable-request/cooldown tests pass; actual notification behavior pending. |
| S10 | Service 238-240, 271-274 | Connected peer supplies malformed input; exception may include payload in system logs. Normal chat is not intentionally logged; log access is OS-dependent. Device disclosure not demonstrated. | Low / suspected payload exposure | Log constant parse warnings without exception objects. Verify malformed synthetic markers in logcat on an owned device; not yet executed. |

The service also enforces the existing 15-second initial-request setup deadline
while the Flutter UI is detached, so moving helper availability to the background
does not bypass S3. No new deadline is imposed on the human approval decision.

## Verification and honest claims

Deadline helper `BleDeadlines` uses independent cancellation tokens for SETUP,
SEND and RECEIVE. Stale callbacks cannot expire replacement timers. Native stop
clears all deadlines. Incoming application setup expires only until the first
valid request; the helper is not forced to decide within a new time limit.

The history policy was selected after the user asked for a recommendation: newest
300 messages, in memory only. The chat UI explains the limit when reached. Old
messages are discarded, not saved elsewhere. Recent incoming ID tracking is capped
at 1024 and resets with the conversation. A changed payload with a recently seen ID
is ignored. IDs outside that window or replayed in a later conversation can be
accepted: this is bounded duplicate suppression, not cryptographic replay defense.
No unbounded seen-ID set, persistence or new dependency was added.

The UI draft cleanup is committed as `f249b07` and verified by a widget regression.
Background chat is volatile: disconnected-session backlog is discarded; oldest
messages beyond 300 are dropped; process death loses all chat. No saved history
or secure erasure guarantee is introduced. Alert cooldown resets when the service
is recreated and does not prevent all radio traffic or reconnect attempts.

See [targeted audit](AUDIT.md) for secrets, logs, backups, checklist applicability,
dependency evidence and unresolved runtime checks.

See [command record](COMMANDS.md) for executed commands and results and
[verification](VERIFICATION.md) for automated and physical checks.
Tests not executed are recorded as pending. Mock Flutter tests do not prove BLE
delivery, encryption or real device cleanup. Native helper tests do not prove
Android callback timing. Passing tests never establish that the app is fully secure.

## Judge-friendly summary

This work aims to preserve user approval, keep conversations separate, and bound
unfinished BLE operations in the already implemented chat. It does not build new
product features or claim authenticated private transport. Actual demonstrated
results are recorded separately as verification completes.
