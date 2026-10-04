# Architecture overview

OfflineRelay's Android MVP keeps the existing BLE transport below a small
Flutter application/controller layer. Chat encryption is applied above BLE;
the native GATT session sees only bounded application envelopes and does not
own cryptographic keys.

```text
Figma-based Flutter UI
        ↓
RelayDemoController and in-memory chat/request state
        ↓
ephemeral key exchange + authenticated encrypted application messages
        ↓
RelayTransport / RelayConnection (256-byte complete-message boundary)
        ↓
Flutter MethodChannel/EventChannel bridge
        ↓
Android BLE GATT session / helper foreground service
```

The controller owns one foreground chat/request at a time. Help Others
advertising remains owned by the Android connected-device foreground service
while the Activity is backgrounded. That service continues to surface incoming
requests through the existing channels and notification. Activity recreation
does not take ownership of or replace the native helper BLE session.

Normal rotation retains Flutter state through the manifest's configuration-change
handling. A genuine Activity/Flutter-engine recreation restores a pending helper
request from the foreground service, but closes an already accepted connection
whose in-memory encryption keys were lost. A fresh session is then required.
The requester session is Activity-owned and stops on leaving the foreground.
Helper advertising survives Activity backgrounding; force-stop/process death
does not restore availability automatically.

Connection/service discovery and GATT transfer deadlines are 15 seconds;
reassembly, outgoing ACK waits and incoming ACK writes have separate timers.
Connection requests expire after 60 seconds and automatic security setup
after two minutes. Application sends are serialized; central GATT data/ACK/read
operations share a serial queue. Remote closure waits for the final transport ACK.

The app layer owns request acceptance, chat messages, terminal chat state,
local report state, and the session cipher. The transport reports complete
messages and disconnect errors. The Android BLE adapter continues to enforce
the 256-byte bound and owns GATT framing, reassembly, application ACKs, and
timeouts.

## Repository boundaries

- `apps/offline_relay/`: Android Flutter host, controller, UI, BLE bridge, and
  application-level session encryption.
- `packages/relay_transport/`: shared peer, connection, profile, and
  versioned-envelope contract.
- `experiments/ble_poc/`: frozen physical-test reference implementation.
- `docs/`: protocol, security, architecture, and validation notes.

No chat/report data is persisted or sent to a backend. Reports remain local to
the current in-memory chat. The app does not currently provide persistent peer
identity or an authenticated trust relationship. Ephemeral key exchange and
encrypted key confirmation happen automatically, with no user verification.
Active man-in-the-middle impersonation is outside this encryption design.
