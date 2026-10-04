# Multiple outgoing iOS connection requests

Validated build checkpoint on `ios-mvp`, based on
`57d8348fd4f3a7b29742925aed7804370ff993fe`.
The tester confirmed physical iPhone validation of the current combined build;
see [the Phase 1 validation record](ios-phase-one-ui.md). Earlier single-chat,
helper background, and local-notification validation records remain historical.

## Ownership and winner selection

Previously the controller kept one request ID/connection/message subscription and
cancelled discovery on Connect. The channel owned one central session; its connect
stopped scanning and required a nil remote peripheral.

Now `_outgoing` stores one pending request per discovery peer ID. Each contains
its own peer, request envelope ID, connection, and message subscription. A duplicate
Connect on the same pending peer is ignored; other cards remain actionable and show
Connect or Requesting… independently. Discovery remains active until acceptance.

The first matching connection_accept claims `_connection` and clears all pending
entries synchronously, before awaiting cleanup. Stream callbacks execute serially
on the Dart isolate. Later events must still belong to a live pending request or
the selected connection; losing accepts, rejects, and chat are ignored. Only the
selected connection can supply chat messages. Rejection, failed connect, or pending
disconnect removes just that request. A late connect result after winner selection,
return to Nearby, or disposal is closed without sending its request.

The winner keeps its existing subscription; disconnect still ends the chat.
Return to Nearby closes the active link and pending links and clears selection.

## Native central isolation

`BleRelayChannels` retains a scanner/profile-probe session independently of a
`BleCentralConnections` registry of peer sessions. Each requested peer receives
its own existing `BleRelaySession`, CBCentralManager, retrieved CBPeripheral,
characteristics, GATT operation queue, receiver, frame ID, outbound transfer,
expected ACK, connection ID, and timeout tokens. The manager obtains its peripheral
using [Apple's retrievePeripherals API](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/retrieveperipherals%28withidentifiers%3A%29)
from the discovered UUID; it does not reuse the scanner's delegate/peripheral.

Registry generation tokens reject events and connect results from removed sessions.
Messages/send/close route by connection ID. Link errors carry connectionId and do
not stop discovery or other connections. Individual sessionEnded events are consumed
by the registry rather than marking the entire Flutter transport scan as stopped.

Cancelling discovery after winner selection or leaving Nearby also stops unresolved
native connects. Ready losing connections are closed through the existing close
method. Background/dispose stops all central sessions. Scanner, pending sessions,
and helper/peripheral owner remain distinct.

RelayTransport and wire methods/envelopes are unchanged; there is no new cancel
message. Losing helpers see the existing disconnect/unsubscribe path, which clears
request notifications and restores helper advertising. Two helpers accepting nearly
together may briefly show chat before the losing link disconnects; only one can
become the Offline User's active chat.

Shared Dart changes are platform-neutral and keep Android method arguments/events
compatible. Android native files are unchanged and still have their prior native
concurrency limits; this checkpoint does not add Android multi-connection support.
No helper server, notification, background-mode, UUID, framing, ACK, or profile
encoding implementation was changed.

## Verification and physical tests

Tests cover B then C, duplicate taps, one rejection/disconnect/failure preserving
others, first accept wins, nearly simultaneous accepts, wrong request correlation,
losing chat rejection, winner duplex chat/disconnect, late connect cleanup, and
return to Nearby. Channel tests cover scoped errors, continued discovery, and C
send/receive routing after B fails. Native registry tests cover isolated contexts,
connection routing, stale tokens, unresolved-connect cancellation, and cleanup.
Existing protocol/helper/notification tests are retained.

Local checks passed: Flutter analysis (no issues), all 30 app tests, native Swift
protocol/helper/notification/central-registry tests, relay transport contract tests,
iOS simulator debug compilation, and git diff --check. The current build was
physically installed and validated on iPhones as confirmed by the tester; no
itemized three-device acceptance-race result was supplied.

Physical tests require at least three iPhones: Offline User A and Helpers B/C
(and D when available). Verify simultaneous requests and notifications, rejection
and disconnect of one pending helper, discovery of additional helpers, acceptance
in either order including a near-simultaneous race, winner bidirectional chat,
loser notification cleanup/availability restart, and return/reconnect. Repeat with
helpers backgrounded/locked. Concurrent radio limits, retrieval, timings, and
losing-helper cleanup should be recorded individually in regression testing. Simulator compilation
is only a build check.
