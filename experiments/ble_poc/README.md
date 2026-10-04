# Throwaway BLE POC — Android only

Status: source implemented; native build and physical-device validation pending.
No platform is currently verified to run this POC. Intended runtime: two
physical Android 12+ (API 31+) phones with BLE; the peripheral must support
advertising. No iOS, desktop, or web BLE implementation is present. This
provisional Android-first choice does not establish final V1 platform support.

## Isolation

This is an independent Flutter app with its own manifest and native source.
It neither imports the product host nor implements the production transport
contract. `MainActivity.kt` bridges diagnostic commands/logs; `BleSession.kt`
owns native GATT state. The Flutter screen has role/send/stop buttons and a
bounded log viewer, not chat. No third-party networking dependency is used.

## Build and run after installing the Android toolchain

Use Flutter 3.47.6 / Dart 3.13.5. From this directory:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter devices
flutter run -d DEVICE_SERIAL
```

Install on both phones. Keep Bluetooth enabled and both apps in the foreground.
Grant Nearby Devices permission, then press the role button again. Only run one
pair in the test area: the central connects to the first matching service UUID.
This automatic selection is for the throwaway experiment only.

1. On B, press **Advertise** and wait for `advertising_started`.
2. On A, press **Discover + connect**; wait for `characteristic_discovered`.
3. On A, press **Send Hello**. Require B's `message_received ... text=Hello`
   and A's `acknowledgement_received` with the matching ID and length 5.
4. On A, press **Send 256 bytes**. Require B's exact `00..ff` vector check and
   A's ACK with matching ID and length 256. Wait for ACK before another send.
5. Stop both sessions, swap roles, and repeat. Capture logs from both phones.

To collect logs with the Android SDK's adb:

```sh
adb -s DEVICE_SERIAL logcat -v time OfflineRelayBLE:I '*:S'
```

Logs include discovery start, discovered address/RSSI, connection, service and
characteristic discovery, sent/received messages, ACK, errors, and stop/disconnect
status. Addresses are local diagnostic data; redact them before sharing logs.
No stronger disconnect cause is fabricated when Android supplies only a status.

## Experiment wire format (not the common application protocol)

| Purpose | UUID / format |
| --- | --- |
| Service | `41729610-0934-4e0e-b749-170442310001` |
| Data, write with response | `41729610-0934-4e0e-b749-170442310002` |
| Application ACK, readable | `41729610-0934-4e0e-b749-170442310003` |
| Data frame | version=1, message ID, zero-based index, frame count, 1–16 payload bytes |
| ACK | version=1, message ID, total length high byte, total length low byte |

Each header field is one unsigned byte. Frames are at most 20 bytes; no larger
MTU is requested. IDs cycle 1–255 within a session. Maximum reassembled payload:
256 bytes, 16 frames. Only `Hello` and bytes 0 through 255 in order are accepted.
Nonfinal frames contain exactly 16 payload bytes. Invalid order/length/version,
prepared writes, overlapping messages, and unrecognized vectors are rejected.

The central issues one GATT write at a time, waits for each callback, then reads
the ACK characteristic after the last successful write response. The peripheral
publishes the ACK only after full reassembly and exact vector validation. This
separates the application ACK from the GATT write response. No notifications,
subscriptions, retries, pairing workflow, or bidirectional chat are implemented.
To test the opposite sending direction, swap the two phones' roles.

Connection, discovery, registration, advertising startup, transfer/ACK, and
reassembly have 15-second deadlines. Idle advertising and an idle established
connection continue until Stop or leaving the foreground. Disconnect clears
pending data. Native callbacks are serialized on the Android main thread.

## Limits and acceptance

Advertising support and permission checks can reject a device. Foreground-only
sessions stop when the activity leaves the foreground. No background guarantee,
peer authentication, encryption policy, Internet check, or production reliability
claim is made. A third device must not be used during baseline tests; one
peripheral connection is allowed. Run only with non-sensitive test vectors.

Flutter tests use mock channels to check command routing and error display;
they do not exercise Kotlin, framing, radios, or delivery. Native framing tests
and actual device results remain outstanding. Follow the full negative-case
[device matrix](../../docs/testing/device-matrix.md) before claiming success.

API references: [Android GATT callbacks](https://developer.android.com/reference/android/bluetooth/BluetoothGattCallback),
[GATT server](https://developer.android.com/reference/android/bluetooth/BluetoothGattServer),
[permissions](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions).

## iOS central POC

The experimental iOS host uses native CoreBluetooth and the exact Android wire
format above. No BLE plugin or product-host dependency is added. iOS peripheral
advertising is not implemented; **Advertise** returns `unsupported_role` on iOS.

Build: `flutter build ios --simulator --debug` from this directory. A simulator
build checks compilation only. For hardware, open `ios/Runner.xcworkspace`, select
the Runner target and a valid signing Team, connect and trust an iPhone, enable
Developer Mode if requested, and run on that device. The POC bundle identifier is
`dev.offlinerelay.experiments.blePoc`; provisioning must cover that identifier.

On a validated Android phone, start **Advertise**. On iPhone, grant Bluetooth
access, press **Discover + connect**, and wait for `central_ready`. Send Hello,
wait for `acknowledgement_received`, then send 256 bytes and wait for its ACK.
Require matching Android `message_received ... exact_payload_verified=true`
logs and iPhone ACK IDs/lengths. Stop and repeat. Keep both apps in the foreground
and only one pair in range. No iPhone physical success has been established.

The iOS central has 15-second scan, connection, service/characteristic discovery,
and combined message-write/ACK deadlines, plus a bounded Bluetooth-readiness
wait. It sends one frame per successful `.withResponse` callback, then reads ACK
once. It does not request larger frames, subscribe, retry, or reconnect. Stop,
background entry, errors, and radio loss detach delegates and cancel pending
operations. Each restart uses a fresh session/manager; timer generation checks
prevent cancelled deadlines from affecting later stages.

Timestamped diagnostics go to the Flutter log viewer and `NSLog` with the
`OfflineRelayBLE` prefix. Use Xcode's device console to preserve logs. A local
`disconnect_requested` or stopped log does not claim a confirmed radio disconnect.

Focused native byte tests run the actual Swift framing helper on macOS:

```sh
xcrun swiftc ios/Runner/BleProtocol.swift test/native/main.swift -o /tmp/offlinerelay-protocol-tests
/tmp/offlinerelay-protocol-tests
```

These tests check byte vectors and framing, not CoreBluetooth delivery or timeout
behavior. Physical permission, missing-peer, missing-ACK, interrupted-transfer,
and radio-off checks remain required.
