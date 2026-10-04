# Android / iOS interoperability preparation: Phase 1

Status: source preparation on Windows, not an iOS build or radio validation.
Branch: `feature/android-ios-interop`. Android reference: local `main` at
`cf59a028907f5e73880db5c014c907b378fd3eea`. The branch was created from clean main
after fetching, then `git pull --ff-only origin main` reported already up to date.
Main retains its local onya-name commit; no main commit was changed or pushed.

## Read-only audit and reuse

Inspected `ios-mvp` at `4cf48653759763549eb77ad14a6c3d4ff1957984`, its six iOS
commits, product Swift/channel code, diagnostic iOS POC, tests and checkpoint
documentation. That branch has real central/peripheral transport and records
user-reported iPhone-pair product/background/notification validation. Those older
results do not validate this preparation or Android/iPhone interoperability.

The older iOS controller sends plaintext chat, lacks main's current secure session,
cancellation and encrypted End Chat, and adds concurrent outgoing requests. Its
application code, UI, dependencies and shared message enums were not copied.
Current Flutter controller, UI, Report, End Chat, envelopes and encryption remain
the source of truth and are unchanged. The frozen POC and Android files are unchanged.

| Existing iOS component | Phase 1 reuse |
| --- | --- |
| `BleFraming.swift` | Copied unchanged: exact DATA frames and ACK encoding |
| `BleMessageReceiver.swift` | Copied unchanged: opaque bounded reassembly |
| `BleRelaySession.swift` | Adapted central portion, GATT queue, ACK reads/writes, notification receive, deadlines and cleanup |
| `BleRelayChannels.swift` | Adapted same methods/events into a single central-session owner |
| `AppDelegate.swift` registration pattern | Registers channels on the current implicit Flutter engine |
| Product native `main.swift` tests | Reused framing/receiver checks, extended with Android profile fixtures |
| Package `contract_test.dart` | Copied dependency-free envelope/profile/byte-limit checks; uses all current message types |
| `BleProfile.swift` | Not copied: its `0004` profile probe is incompatible with current Android |
| Helper availability/state/notifications, central multi-link registry | Not copied: later phases are out of scope |
| iOS POC | Read-only reference; its receiver only accepts diagnostic vectors, unlike the product receiver |

## Exact compatibility

| Item | Existing Android | Prepared iOS requester |
| --- | --- | --- |
| Primary service | `41729610-0934-4e0e-b749-170442310001` | Same service filter/discovery |
| DATA | `41729610-0934-4e0e-b749-170442310002`, write + notify | Writes with response; subscribes to notifications |
| ACK | `41729610-0934-4e0e-b749-170442310003`, read + write | Reads ACK after final write; writes ACK after full notification reassembly |
| Profile | Scan-response service data under the service UUID | Reads `CBAdvertisementDataServiceDataKey` under the same UUID |
| Advertisement | Connectable legacy service UUID advertisement; profile in scan response | Scans that service; does not advertise |
| Profile bytes | `[1, role, UTF-8 length, label...]`; role 1=requester, 2=helper; label at most 10 UTF-8 bytes | Strict decoder emits existing `{id,label,metadata:{role}}` peer map |
| Frame | `[1, messageId, index, count, payload...]` | Unchanged iOS framing/receiver |
| Frame size | 4 header + 1..16 payload bytes; 5..20 total | Same |
| Message size | 1..256 bytes; at most 16 ordered frames | Same |
| Message IDs | Per-direction 1..255, then wrap to 1 | Same |
| ACK bytes | `[1, messageId, length >> 8, length & 255]` | Same |
| GATT sequencing | Serialized client DATA writes, ACK reads, reverse ACK writes | Same operations share one queue |
| BLE deadlines | 15 seconds for stages, message/ACK and reassembly | Independent 15-second readiness, discovery, connection/service, GATT operation, message/ACK, reassembly and close-drain deadlines |
| Application deadlines | 60-second request, two-minute automatic key setup | Existing shared controller unchanged |

Source comparison establishes the same wire layout: Hello with ID 1 is
`01 01 00 01 48 65 6c 6c 6f`, ACK `01 01 00 05`; a 256-byte message has sixteen
20-byte frames and an ACK length of `01 00`. The Swift receiver does not parse JSON,
classify envelope types, or special-case ciphertext. Source compatibility and
prepared byte fixtures are not evidence of actual CoreBluetooth delivery.

## Phase 1 behavior

1. The foreground iPhone requester scans for the existing Android service.
2. Android profile bytes become ordinary RelayPeer metadata. The current Flutter
   helper filter selects `internet_helper`. Malformed/unknown profiles are ignored;
   no guessing based on device names or connection to a `0004` characteristic.
3. The user can select a retained discovered peer after scanning stops. Connect
   stops scanning but does not cancel its own connection deadline.
4. The central discovers DATA/ACK, checks properties/capacity and enables DATA
   notifications. Native connect completes only after subscription succeeds.
5. Flutter performs the existing request, explicit Android acceptance, automatic
   key exchange/confirmation, encrypted bidirectional chat, Report and End Chat.
6. Incoming notification ACKs enter the queue before message delivery to Flutter.
   Local close waits for pending inbound ACK writes, bounded by a deadline. This
   is needed when Flutter receives encrypted End Chat and immediately closes.
7. Disconnect, Bluetooth loss, background entry and listener detach release the
   requester session, pending methods, timers, handles and delegate ownership.
   A retry creates a fresh session; no automatic reconnection is added.

The iPhone transport implements the existing channels:
`dev.offlinerelay/ble/methods` and `dev.offlinerelay/ble/events`. No Dart factory or
transport-interface change is needed: native registration supplies the platform
adapter. Denied iOS access uses a native recovery message that avoids the current
controller's Android-specific permission wording. Info.plist adds the Bluetooth
usage description. No background mode, helper notifications or restoration is added.

The existing Help Others control remains visible because UI was not redesigned.
On iPhone, `advertise` returns an explicit Phase 1 unsupported error; stop-helper
and stop-advertising are safe no-ops. Android requester / iPhone helper and iOS
background helper interoperability are not enabled. No iOS-pair claim is made for
this central-only preparation; the original `ios-mvp` branch remains untouched.

## Encryption and product preservation

`RelaySecureSession` and controller remain unchanged: ephemeral X25519, HKDF-SHA-256
directional keys, AES-256-GCM, automatic encrypted key confirmations, counters and
the complete 256-byte envelope limit. Swift transports these bytes and never logs
payloads or keys. There is no Swift encryption or manual verification screen.
Active peer impersonation/MITM remains outside the existing protection.
Report remains local/in-memory; no new backend or persistence is added.

## Checks available on Windows

- Repository-root `flutter analyze`: passed, no issues.
- App `flutter test`: passed, 38 tests (36 existing + 2 channel-contract tests).
- `dart analyze packages/relay_transport`: passed, no issues.
- `dart packages/relay_transport/test/contract_test.dart`: passed.
- Repository consistency checks: passed for protected source paths/branch refs,
  byte-identical reused helpers, Bluetooth plist declaration, unique Xcode object
  IDs/source membership and matching UUIDs. Limited Swift lexical delimiter checks
  passed; these are not Swift parsing, compilation or type checking.
- `git diff --check` and new-file whitespace review: passed; no generated output,
  signing files or credentials are included in the change list.
- New channel tests exercise typed encrypted messages, confirmation/chat/End Chat
  bodies, both cipher directions, native send-future completion and disconnect.
  Native channel results are mocked; the tests do not run Swift or validate ACK radio timing.
- Swift/Xcode tools are unavailable on this Windows host. No Swift compilation,
  Swift fixture execution, iOS build, install or physical-device test was performed.

## Required Mac handoff

Use a compatible Flutter SDK (reference 3.47.6 / Dart 3.13.5), Xcode with iOS SDK,
and a physical iPhone. The existing project targets iOS 15+ and bundle ID
`dev.offlinerelay.offlineRelay`. Configure signing locally in Runner.xcworkspace;
do not commit a team, provisioning profile or machine-specific build files.

First run the actual Swift helper fixtures (Foundation only):

```sh
xcrun swiftc apps/offline_relay/ios/Runner/BleFraming.swift apps/offline_relay/ios/Runner/BleMessageReceiver.swift apps/offline_relay/ios/Runner/BleAndroidProfile.swift apps/offline_relay/test/native/ios_interop/main.swift -o /tmp/offlinerelay-ios-interop-tests
/tmp/offlinerelay-ios-interop-tests
```

Then compile the iOS app, install on an iPhone, and validate against the unchanged
Android helper: service-data visibility in CoreBluetooth, profile/role decoding,
request and acceptance, overlapping key exchange, encrypted chat both ways, both
End Chat directions and final ACK drain, Report, reject/cancel, disconnect/retry,
Bluetooth off, denied access and leaving the requester app. Simulator compilation
does not establish radio compatibility. Do not declare Phase 1 working before
this physical run. The main risks still needing hardware evidence are scan-response
delivery/callback timing, duplex GATT queues, final ACK/disconnect timing and OEM/iOS
behavior under failure.
