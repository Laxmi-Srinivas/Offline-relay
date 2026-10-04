# ADR-001: transport-independent application architecture

Status: accepted direction from the project brief; initial contract implemented.
Date: 2026-10-04

MVP outcome: the boundary now has an Android native BLE adapter with API 31
minimum, 256-byte envelopes, background helper service and application encryption.
LAN and iOS remain unimplemented. The original decision/context below is preserved
as history; current limits are in `docs/testing/deployment-readiness.md`.

## Context

OfflineRelay intends to connect nearby phones and laptops without requiring
Internet connectivity on both devices. One networking mechanism is not assumed
to cover every device combination.

## Decision

Place a transport abstraction below the application layer and Flutter UI.
Investigate BLE GATT first for phones, including central and peripheral roles.
Investigate mDNS/Bonjour plus TCP or WebSocket separately for LAN use.
Keep the first BLE experiment isolated and disposable. Derive final adapter
requirements from measured behaviour instead of promoting the POC wholesale.

## Consequences

The common application protocol can eventually run over multiple transports.
Adapters own discovery details, native API integration, fragmentation/framing,
and transport error translation. Platform support must be tracked independently
for each role and device pair. More than one adapter will need validation.

The final contract, LAN data-channel choice, OS minimums, Bluetooth dependency,
and background behaviour remain open. No Wi-Fi Aware, Wi-Fi Direct, tunnelling,
backend, or production feature implementation is included in this decision.

The provisional first experiment targets two Android 12+ devices because the
test phone pair was not supplied. Native GATT APIs are isolated in that app;
this is not a decision to exclude iOS from V1 or adopt native-only production
adapters. The experiment uses a readable application ACK characteristic rather
than notifications. No third-party BLE dependency is selected yet.
