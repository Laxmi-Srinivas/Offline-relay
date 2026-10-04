# OfflineRelay V1 scope

## Product goal

An offline user discovers a nearby willing helper, connects locally, exchanges
chat messages, and eventually receives the result of an Internet-dependent task
performed by that helper. The helper's Internet connection is not shared or
tunnelled. Local connectivity and Internet availability are separate concerns.

## Current implementation milestone

Establish a Flutter foundation and investigate a throwaway BLE exchange:
discovery → connection → GATT service/characteristic discovery → `Hello` →
slightly larger payload → application acknowledgement. Keep both apps open in
the foreground. No chat UI is required; diagnostic controls/logs are sufficient.

BLE is the first phone-to-phone candidate. LAN discovery through mDNS/Bonjour
where supported, followed by TCP or WebSocket, is the laptop/shared-network
candidate. LAN is not implemented in this milestone.

## Intended targets, not verified support

Android and iOS phones; Linux, macOS and Windows laptops. Exact OS minimums and
device support require toolchain and physical-device validation. The first phone
pair is provisionally two Android 12+ phones, awaiting confirmation of actual
hardware. See [device matrix](../testing/device-matrix.md).
No browser target is required.

## Explicit exclusions

No final UI, chat product, service requests, accounts, backend, persistence,
production security, routing, automatic helper selection, Internet availability
verification, Internet tunnelling, Wi-Fi Aware, Wi-Fi Direct, or complex native
peer-to-peer technologies. No background-operation guarantee. Experiments must
use non-sensitive test data and must not be presented as production ready.
