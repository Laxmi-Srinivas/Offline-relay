# Architecture direction

This document records the original architecture direction, including future LAN
plans. The Android BLE chat and background-helper implementation now exist;
LAN/Internet relay actions remain unimplemented. For the current source-based
architecture, trust boundaries and security verification, see
[security work record](../security/README.md). Historical contributor device results
and Security's independent checks must be read separately.

```text
Flutter UI
    ↓
Application layer (transport-independent messages and use cases)
    ↓
Transport abstraction
    ├── BLE adapter → native GATT central/peripheral APIs
    └── LAN adapter → mDNS/Bonjour discovery + TCP or WebSocket
```

The application layer must not import native Bluetooth APIs, plugin-specific
types, sockets, or WebSocket types. The future transport boundary will expose
peer discovery, connection lifecycle, complete message delivery, and explicit
errors. BLE fragmentation and stream framing belong below that boundary.
Application acknowledgements must not be confused with transport write success.

## Repository layout

- `apps/offline_relay/`: minimal Flutter host; no final UI.
- `packages/relay_transport/`: pure Dart transport contract.
- `experiments/ble_poc/`: independently runnable, disposable BLE experiment.
- `docs/`: scope, decisions, protocol hypotheses, and validation evidence.

The host must not depend on the BLE experiment. The experiment may test an
independent wire format and native integration. Its findings will inform a later
adapter; its code is not automatically the final architecture. No production
adapter is approved merely because an experiment compiles.

The initial `RelayTransport`/`RelayConnection` contract covers discovery, outbound
connection, bounded complete-message streams, sends, and disposal. It is
provisional: inbound-session acceptance and structured disconnect events must
be designed from POC findings before implementing the final adapters. The
placeholder host depends only on this package; it starts no network activity.
