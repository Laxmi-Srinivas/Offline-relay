# iOS product adapter checkpoint

Working branch: `ios-mvp`. Inspected main commit:
`e402922d80f9830bce08a752dc8a1e05a895bd30` (`feat: simplify MVP to peer chat`).
Base iOS diagnostic physical-validation checkpoint:
`b9d038cefe85bb3d8e9aefc1277fa098c5edc141`.

No merge, rebase, or PR. Local signing settings are excluded from this checkpoint.
All tracked diagnostic files and Android implementation files remain byte-identical
to the base checkpoint. The diagnostic app remains the known-good reference;
its physical result does not validate this product adapter.

## Shared product sync

Main's relevant changes since the common checkpoint are `508b78d` (Android
transport/product foundation) and `e402922` (Nearby Users / peer chat flow).
Copied exactly: app `lib/main.dart`, `lib/relay_demo_controller.dart`,
`lib/transport/ble_relay_transport.dart`, three existing app test files, and
`packages/relay_transport/lib/relay_transport.dart`. Package pubspec is unchanged.
All eight main files under the selected lib/test/package paths match byte-for-byte.
Android source, manifests, and Gradle files were inspected but not copied.

The platform-neutral screens, wording, roles, helper filtering, request/accept/
reject/chat JSON envelopes, 24-character display-name input, 160-character chat
input, and back-button behavior are identical to the inspected main commit.
No iOS branches were added to Dart business logic. Additional tests do not alter
those copied files. The bridge's existing Android-specific doc comment is retained
because the shared source is copied exactly; its channel contract serves iOS too.

## Native host implementation

`BleFraming` and `BleMessageReceiver` adapt the validated iOS diagnostic helpers:
version 1, message ID 1..255, zero-based frame index/count, up to 16 payload bytes,
up to 16 frames/256 total bytes, strict ordering, and big-endian-length ACK.
The product receiver accepts arbitrary bytes; it does not special-case test vectors.

Main's product adds DATA notifications and ACK writes to the same UUIDs. The
adapter implements those additions with CBCentralManager/CBPeripheral and
CBPeripheralManager/CBMutableService/CBMutableCharacteristic:

| Component | UUID / properties |
| --- | --- |
| Primary service | `41729610-0934-4e0e-b749-170442310001` |
| DATA | `41729610-0934-4e0e-b749-170442310002`, write + notify |
| ACK | `41729610-0934-4e0e-b749-170442310003`, read + write |
| iOS profile extension | `41729610-0934-4e0e-b749-170442310004`, read |

Central sends sequential writes-with-response, then reads ACK. Peripheral sends
ordered notifications, respects updateValue backpressure, then awaits the central's
ACK write. Send futures complete only on an exact application ACK, as on main.
Central GATT reads/writes (including reverse-message ACK writes) share a serialized
queue. Reassembly and outgoing transfer have independent 15-second deadlines,
avoiding receive activity cancelling an outgoing ACK deadline. Invalid write
batches are rejected atomically, with bounded state cleanup. Stop/background/
radio failure terminates pending methods and releases owned resources. Each new
session uses fresh delegates and generation-guarded deadlines.

A helper emits incomingConnection only after the central subscribes to DATA.
The shared controller then waits for connection_request before offering Accept/
Reject. Connection acceptance is a Dart envelope, not automatic native approval.
StopAdvertising retains an established link so acceptance/chat can continue.
Central disconnect, peripheral unsubscribe, and service invalidation drive cleanup;
CoreBluetooth does not offer arbitrary peripheral-side force-disconnect. Removing
services and stopping advertising ends local state; peer observation needs hardware
validation. No background BLE capability or state restoration is promised.

## Exact Flutter channel contract

MethodChannel: `dev.offlinerelay/ble/methods`.

| Method | Arguments | Success |
| --- | --- | --- |
| advertise | `{profile: {id: String, label: String, metadata: Map<String,String>}}` | null, after advertising starts |
| startDiscovery | none | null, after scanning starts |
| stopDiscovery | none | null |
| connect | `{peerId: String}` | `{connectionId: String, peer: peerMap}`, after discovery/subscription |
| send | `{connectionId: String, message: Uint8List}` | null, after matching ACK |
| close | `{connectionId: String}` | null |
| stopAdvertising | none | null |
| dispose | none | null |

Invalid methods use FlutterMethodNotImplemented. Invalid arguments/state, native
failure, or deadline failure return `ble_error`; denied Bluetooth permission returns
`permission_denied`; advertising-start failure returns `advertise_error`. Errors
have a string message and null details. iOS system permission prompting replaces
Android's Nearby Devices prompt. Bluetooth-off/unsupported state is reported, not
silently treated as success.

EventChannel: `dev.offlinerelay/ble/events`. Events are ordinary maps:

- `{event: peerDiscovered, peer: peerMap}`
- `{event: incomingConnection, connectionId: String, peer: peerMap}`
- `{event: message, connectionId: String, message: Uint8List}`
- `{event: disconnected, connectionId: String, reason: String}`
- `{event: error, message: String}`
- `{event: sessionEnded, reason: String}`

peerMap is `{id: String, label: String, metadata: Map<String,String>}`. Role is
`metadata.role` (`internet_helper` or `offline_user`), not a new top-level field.
Message events use FlutterStandardTypedData so Dart receives Uint8List.

## Discovery metadata differences

iOS's advertising API supports service UUIDs and local name, not Android's custom
service-data scan-response profile. Advertise the existing service UUID and a
UTF-8-safe, at-most-10-byte name containing `ORH:` or `ORU:` plus a short label.
Because local name packing is best-effort, discovery does not rely on that name.

The scanner briefly connects to matching services, reads the complete JSON profile
from the added read characteristic, then disconnects before emitting peerDiscovered.
This obtains the full label and metadata for Dart's helper filter. The probe never
subscribes to DATA and never emits incomingConnection or sends an application
request. Probes are sequential, bounded, cancelled on stop/connect, and unrelated
or diagnostic services without a profile are skipped. The user-visible Connect
button makes the actual subscribed chat link; full profile is refreshed there.
Discovery IDs are opaque CoreBluetooth identifiers; the full profile includes the
advertiser's application ID. Profile JSON is bounded at 512 bytes; long reads
support ATT offsets. Message envelopes retain the unchanged 256-byte limit.

This discovery extension is specific to the new iOS product hosts. Main's Android
advertisement uses compact service data and lacks this profile characteristic;
Android/iOS discovery interoperability is not claimed or tested here. Any later
cross-platform metadata alignment belongs in a separately authorized change.

## Verification

- Real app `flutter analyze`: passed, no issues.
- Real app `flutter test`: passed, 12 tests (9 copied tests + 3 channel-contract tests).
- `dart analyze packages/relay_transport`: passed, no issues.
- Dependency-free package test: `dart packages/relay_transport/test/contract_test.dart`, passed.
- Native product tests: exact validated framing, all payload lengths 1..256,
  arbitrary UTF-8 envelopes, ACKs, malformed ordering, receiver reset, duplex
  state isolation, and full/compact profile encoding: passed.
- Real app `flutter build ios --simulator --debug`: passed;
  artifact `apps/offline_relay/build/ios/iphonesimulator/Runner.app` (ignored).
- `git diff --check`: passed.
- `git diff b9d038ce HEAD -- apps/offline_relay/android`: empty. Working-tree Android
  diff is also empty; protected files are compared byte-for-byte, not just HEAD.

Native tests run actual product helpers:

```sh
xcrun swiftc apps/offline_relay/ios/Runner/BleFraming.swift apps/offline_relay/ios/Runner/BleMessageReceiver.swift apps/offline_relay/ios/Runner/BleProfile.swift apps/offline_relay/test/native/main.swift -o /tmp/offlinerelay-product-tests
/tmp/offlinerelay-product-tests
```

Tests/build do not establish CoreBluetooth callback timing, discovery probing,
backpressure, peer teardown, or physical delivery by themselves. Physical product
results reported by the user are recorded separately below. No signing Team is committed; use local signing for bundle identifier
`dev.offlinerelay.offlineRelay`.

## Physical real-app validation — 2026-10-04

The user reported successful product-level validation of `apps/offline_relay` on
two real iPhones in both role assignments. This was the real Nearby Users / peer
chat application, not a simulator and not `experiments/ble_poc`.

| Internet Helper | Offline User | Offer Help / Find Nearby Helpers / discovery | Connect / request / Accept / enter chat | Chat helper → offline user | Chat offline user → helper |
| --- | --- | --- | --- | --- | --- |
| iPhone A | iPhone B | Passed | Passed | Passed | Passed |
| iPhone B | iPhone A | Passed | Passed | Passed | Passed |

This records the user's physical test report. Per-run device/OS assignments,
message contents/IDs, and raw device logs were not supplied for attachment.
Earlier device enumeration showed an iPhone 14 Pro and an iPhone 14; enumeration
alone does not prove which device held each role during a given run.

The earlier BLE diagnostics physical validation at `b9d038ce` proved Hello and
256-byte `00..ff` transfers with ACKs using the disposable experiment. This current
product validation additionally proves the reported discovery, application
connection approval, chat entry, and messages in both directions using the real
Flutter product flow. The diagnostic source remains intact and separate.

## Remaining validation

Reject, overlapping sends, UTF-8/byte-limit boundaries, back-button teardown,
reconnect, absent peers, permission denial, Bluetooth off, background entry,
interrupted messages, missing ACK, and timeout cases have not been reported as
validated in this product run. Record those separately rather than inferring them
from the successful baseline. No Android ↔ iPhone test was performed in this phase.

Main's UI permits 160 characters, but the complete UTF-8 JSON must fit in 256 bytes;
a plain 160-character ASCII message encodes to 246 bytes, while Unicode or
JSON-escaped text may exceed the limit. This inherited
behavior is preserved, not expanded. Main's controller also retains its current
role-switch/error recovery behavior; broader UI recovery changes were not added.
