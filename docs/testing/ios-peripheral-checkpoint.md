# iOS peripheral and physical-validation checkpoint — 2026-10-04

Scope: `ios-mvp`, iOS ↔ iOS only. No Android work or cross-platform device tests.
The original central session and protocol helper are unchanged.

Native `CBPeripheralManager` publishes the existing primary service with dynamic
DATA write and ACK read characteristics. `BleReassembler` validates bounded,
ordered version-1 frames and exact Hello/00..ff payloads. ACK bytes and central
sequencing remain unchanged. Role commands stop the prior role before creating
a fresh session. Stop/background/radio loss clear state and detach delegates.

Peripheral CoreBluetooth exposes ATT interactions rather than a generic link
connect/disconnect event. Reassembly expires in 15 seconds; an idle peer/ACK lease
also expires in 15 seconds. This bounds stale state after a silent disconnect,
but immediate disconnect-triggered cleanup cannot be demonstrated by these APIs.
No subscription or protocol change was introduced to work around that limitation.

## Verification

- Native central wire tests plus peripheral reassembly/ACK tests: passed.
- Tests include malformed version/length/count/ID, missing/skipped/duplicate
  frames, overlapping messages, changed ID/count, corrupt full vector, ACK
  withheld until completion, reset/recovery, and candidate-state isolation.
- CoreBluetooth timer, delegate, advertising, ATT response, and physical delivery
  behavior require hardware checks; helper tests do not establish those results.

## Build/test results

- POC `flutter analyze`: passed, no issues.
- POC `flutter test`: passed, 3 tests including iOS role controls.
- Existing product-host `flutter test`: passed, 1 smoke test.
- POC `flutter build ios --simulator --debug`: passed;
  artifact `build/ios/iphonesimulator/Runner.app` (ignored build output).
- `git diff --check`: passed.
- All 39 tracked Android files match HEAD byte-for-byte and the empty baseline.
- `BleCentralSession.swift` and `BleProtocol.swift` match HEAD byte-for-byte.
- Product host and shared transport contract have no changes.

## Physical iPhone ↔ iPhone validation

The user reported successful validation on two physical iPhones on 2026-10-04.
These were real-device BLE runs, not simulator runs. Both role assignments passed:

| Central | Peripheral | Hello transfer | Hello ACK | Exact 256-byte 00..ff transfer | 256-byte ACK |
| --- | --- | --- | --- | --- | --- |
| iPhone A | iPhone B | Passed | Passed | Passed | Passed |
| iPhone B | iPhone A | Passed | Passed | Passed | Passed |

This records the user's physical test result. Device logs, message IDs, and
per-run hardware/OS assignments were not supplied for attachment to this record.
Earlier device enumeration showed an iPhone 14 Pro (iOS 26.6.2) and an iPhone 14
(iOS 26.6.1); that enumeration alone is not evidence of a specific role assignment.

The baseline iPhone-to-iPhone exchange is validated in both directions. Negative
cases (permissions, radio loss, missing ACK, partial transfer, timeout, restart)
remain unverified unless separately recorded. No Android ↔ iPhone testing was
performed in this phase. Local DEVELOPMENT_TEAM settings are excluded from the
repository checkpoint; each developer configures signing locally.
