# iOS helper availability parity checkpoint

Branch: `ios-mvp`; base physically validated product commit:
`887bc13467a3aecebf3dc20792e190f022e72e5c`.
Inspected exact main diff:
`e402922d80f9830bce08a752dc8a1e05a895bd30` →
`a504c3fa26ab24a9218693fdfe9004cbe1aad758`.

Android and diagnostics remain unchanged. This checkpoint was developed on
`ios-mvp` without merging or rebasing main.

The earlier foreground peer-chat validation belongs to the base product checkpoint.
The separate physical test below validates the new background helper lifecycle;
it does not validate process restoration or force-quit availability.

## What main added

- Enable Help Others / Disable Help Others UI and availability wording.
- App-level HelperAvailabilityControl with availabilityStates,
  acceptedConnections, and stopHelperAvailability().
- stopHelper method and helperState/helperAccepted channel events.
- Controller reconstruction of helper role/name/availability and accepted links.
- Reject retains helper availability instead of permanently disabling it.
- Android BleRelayForegroundService owns helper BLE independently of the Activity,
  replays pending requests/acceptance on attachment, restarts advertising after a
  connected session ends, and displays ongoing/request notifications. It uses
  START_NOT_STICKY; Android boot/indefinite persistence is not inferred from that.

Shared main.dart, ble_relay_transport.dart, helper_availability.dart, and main's
controller tests were copied exactly from a504c3f. The package transport/envelope
code did not change in this main diff and is unchanged here.

One platform-neutral controller fix differs from main: clear the closed incoming
connection after Reject, and release ended current/incoming references on error
or stream completion. Otherwise the next helper request is immediately closed by
the existing one-link guard even after native advertising restarts. Late callbacks
from replaced connections are ignored. Tests cover Reject → next request → Accept
and disconnected accepted chat → new request → Accept. No platform checks were
added to shared Dart business logic; UI wording remains identical to main.

## Native changes

- AppDelegate retains BleHelperAvailability for the app lifetime, outside the
  Flutter channel listener. It reconstructs saved availability at app launch
  before relying on the Flutter engine to handle BLE events.
- BleHelperAvailability owns the peripheral session, saved profile/enable choice,
  request/acceptance replay, and generation-guarded advertising restart.
- BleHelperState is a Foundation-only, tested replay snapshot. In-process
  connection IDs/pending request/accepted state can be replayed to a reattached UI.
  Up to 32 recent undelivered chat messages are retained when no listener exists.
  This bounded queue is not persistent chat history or an exactly-once guarantee.
- BleRelayChannels routes helper advertise/send/close separately from central
  operations. Background entry stops only the Offline User central session.
  Listener cancellation/dispose does not disable helper availability; stopHelper
  explicitly disables it. Disposal can still close an active Dart connection.
- BleRelaySession opts its helper peripheral manager into restoration with
  `dev.offlinerelay.helper.peripheral` and implements willRestoreState.
- Info.plist includes only UIBackgroundModes = [bluetooth-peripheral]. No
  bluetooth-central mode, new signing entitlement, or Android-style service.

All existing service/DATA/ACK/profile UUIDs, frame layout, 256-byte message bound,
ACK encoding, sequential central writes, reverse notifications, and profile reads
are preserved. BleFraming.swift, BleMessageReceiver.swift, and BleProfile.swift
are byte-identical to the validated product checkpoint. The central code paths
and background stop behavior are retained.

## New channel contract

Existing channel names and methods/events remain. Add:

- `stopHelper` (no arguments): stop advertising/session, clear pending helper
  snapshots, cancel any scheduled restart, and save the enable choice as false.
  Returns null.
- `{event: helperState, enabled: bool, displayName?: String}`: emitted on native
  enable/disable/failure and replayed when a live helper UI listener attaches or
  the app resumes. enabled describes the user's active Help Others choice after
  startup succeeds; it is not a measurement of uninterrupted OS advertising.
  An accepted chat may have advertising paused while this choice remains true.
- `{event: helperAccepted, connectionId: String, requestId: String, peerName: String}`:
  emitted only after a matching connection_accept payload completes its application
  ACK. Request correlation and peer name come from the received connection_request.
  Replayed with incomingConnection before acceptance when reconstructing the UI.

Replay order is helperState, incomingConnection, pending request message (if any),
helperAccepted (if any), then buffered chat. A disabled helper with no live session
is not replayed on every foreground entry, avoiding overriding a later Offline User
role selection. The explicit disable action still emits helperState(false).

Accept pauses advertising and preserves the link. Reject closes the current link;
if Help Others is enabled, native restart occurs after 500 ms with the saved profile.
Explicit Disable invalidates that restart. Initial advertising or radio failures
report the existing errors and disabled helper state rather than pretending to
remain reachable. Acceptance remains a foreground user decision; there is no
background auto-accept.

## iOS background expectations and limits

With bluetooth-peripheral, iOS can advertise and wake the app for peripheral
read/write/subscription requests. Background advertising omits local name and
places service UUIDs in the overflow area; discovery requires an iOS central
explicitly scanning for that UUID. Advertising may be less frequent. The existing
scanner already filters the exact UUID and obtains complete metadata through the
profile characteristic, so it does not depend on the local name.
[Apple background guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html),
[Apple advertising API](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/startadvertising%28_%3A%29).

This allows short BLE-event work while iOS schedules it, not a continuously running
Flutter isolate or a foreground service. Timers may run late during suspension;
15-second protocol deadlines do not grant 15 seconds of background CPU execution.
There is no Android-style persistent foreground-service notification. Native local
connection-request notifications are described below; notification delivery is
subject to authorization and system settings. A background request is still
retained for the UI on resume; no automatic request acceptance is performed.

The peripheral restoration identifier asks CoreBluetooth to preserve eligible
published services/advertising. On relaunch, compatible services without live
subscribers can be adopted. If live subscriptions or incompatible services are
restored, the adapter removes/rebuilds services to invalidate old in-flight chat
state rather than reusing lost message IDs, ACK state, and Dart connections.
Only the profile/enable choice is stored in UserDefaults. Normal app launch can
re-enable that choice. Active chats, ACKs, pending requests, and message history
are not recovered after process death; the peer must reconnect.

CoreBluetooth relaunch is conditional on pending BLE activity and OS rules. Treat
user force-quit as making this phone-to-phone app unavailable until manually opened.
Apple's current TN3115 documents iOS 26 AccessorySetupKit exceptions for certain
relaunch cases; this app does not use accessory setup and claims no such exception.
Bluetooth toggling and device restart/unlock also require hardware checks. We do
not promise Android-equivalent indefinite availability after leaving/terminating
this app. [Apple relaunch rules](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules).

Offline User scanning/chat remains foreground-only. No central background mode
or central restoration ID is needed for this selected helper-only scope.

## Verification and device work remaining

- Flutter analysis: passed, no issues.
- App tests: 19 passed, including prior chat, copied availability test, and new
  enable/disable, helperState, helperAccepted/replay, duplicate replay, Reject →
  Accept-next, disconnect → Accept-next, and bidirectional chat checks.
- relay_transport analysis and dependency-free contract test: passed.
- Native Swift helpers: passed original wire/profile tests and helper replay-state
  tests for pending requests, acceptance correlation, rejection/close retention,
  bounded unread buffer, and disable cleanup.
- iOS simulator compilation: passed; this is not background BLE validation.
- git diff --check and protected-file comparison: passed.

Native helper tests now include BleHelperState.swift:

```sh
xcrun swiftc apps/offline_relay/ios/Runner/BleCentralConnections.swift apps/offline_relay/ios/Runner/BleFraming.swift apps/offline_relay/ios/Runner/BleMessageReceiver.swift apps/offline_relay/ios/Runner/BleProfile.swift apps/offline_relay/ios/Runner/BleHelperState.swift apps/offline_relay/test/native/main.swift -o /tmp/offlinerelay-helper-tests
/tmp/offlinerelay-helper-tests
```

## Physical background helper validation — 2026-10-04

The tester reported successful validation in the real `apps/offline_relay` app on
two physical iPhones, not a simulator. Both devices were visible to Flutter and
received debug builds before the test:

- Jubilee high school 5G — iOS 26.6.2.
- Laxmi Srinivas’s iPhone — iOS 26.6.1.

Reported passing behavior:

- Internet Helper enables Help Others and moves the app to background.
- The foreground Offline User still discovers that helper.
- The Offline User sends a connection request while the helper is backgrounded.
- Returning the helper to foreground shows the pending request.
- Accept succeeds and chat messages work in both directions.
- Reject leaves helper availability enabled.
- Another connection succeeds without re-enabling Help Others.
- Reconnect succeeds.

This is background helper-availability validation, distinct from the earlier
foreground peer-chat checkpoint and the older `experiments/ble_poc` diagnostic
Hello/256-byte validation. The new report does not establish both role assignments
or locked-screen behavior unless separately tested. Debugger-attached device
success does not establish behavior during prolonged OS suspension or relaunch.

## Remaining unvalidated cases

Process preservation/restoration, system termination/relaunch, force-quit, device
restart/unlock, locked-screen discovery, prolonged suspension, and detached release
build behavior remain unvalidated. No force-quit or indefinite-availability claim
is made. Active chats and pending requests are not persisted across process death.

Also test Disable/re-enable, delayed-restart cancellation, listener detach/reattach,
peer loss, Bluetooth off/on, missing ACK, and timer expiry. Exercise eligible system
restoration separately from manual reopening after force-quit; debugger termination
is not equivalent to all OS termination cases. Capture device models, app revision,
both device logs, and observed limits for those tests.

## Native local connection-request notifications — validated checkpoint

Physical local-notification validation **passed**, as reported by the tester on
real iPhones using the release builds launched on the two devices listed above.
This is a separate validation from the earlier foreground peer-chat and background
helper-availability checkpoints. It is not simulator validation.

- Uses native `UNUserNotificationCenter`, without a Flutter notification plugin,
  APNs registration, push entitlement, background mode change, or signing change.
- Enabling Help Others checks authorization and requests alert/sound permission
  only when status is not determined. BLE startup does not wait for the result.
  Denial/error leaves helper availability and pending-request replay intact.
  Previously denied permission must be changed in iOS Settings; no repeated prompt.
- The existing `BleHelperState.receive` request parser returns a descriptor only
  for version-1 connection_request envelopes with nonempty ID, map body, exactly
  the existing four envelope fields, and at most 256 bytes. Notifications do not
  independently decode a protocol. Missing name uses the existing Nearby user
  fallback. The wire format and message ACK behavior are unchanged.
- Title: `Someone nearby needs help`. Body: `<peer name> sent you a connection request`.
  Uses default sound, immediate local delivery, and identifier
  `offlinerelay.request.<request ID>` to namespace alerts belonging to this feature.
- Request IDs are deduplicated in a bounded, process-local cache of the most recent
  256 IDs, including requests handled in foreground or without permission. Replays
  do not reschedule alerts. A new request ID can notify after Reject/reconnect.
- Scheduling requires helper enabled, authorized/provisional permission, and app
  not active. Foreground banner/sound is suppressed; the existing incoming-request
  UI remains the presentation. The AppDelegate also suppresses foreground delivery
  if app state changes between scheduling and delivery.
- Matching Accept/Reject clears pending and delivered alerts after the outgoing
  response receives its application ACK. Disconnect/session end, helper disable,
  or replacement of the helper session/request clears the relevant alert as well.
  Generation tokens prevent late settings/add callbacks from leaving stale alerts.
- Launch removes orphaned feature alerts because pending BLE requests do not survive
  process death. Ordinary notification tap foregrounds the app and leaves the
  existing request replay intact. There is no notification auto-accept/deep link.
- FlutterAppDelegate remains the notification delegate; unrelated notifications
  are forwarded to superclass callbacks. No custom notification actions are added.

Foundation-only native tests cover request-ID deduplication, authorization and
foreground scheduling decisions, Accept/Reject cleanup, disconnect/end/disable
invalidation, new requests, stale callback tokens, and malformed envelopes.
They do not test system alert delivery or substitute for real-device testing.
See [Apple notification delegate documentation](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate)
and [notification center API](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter).

Physical results reported passing:

- Helper enabled Help Others, then backgrounded the app / locked the phone.
- Incoming connection request produced a native iOS local notification.
- Notification appeared on the lock screen.
- Tapping opened OfflineRelay with the pending connection request still available.
- Accept cleared the request notification.
- Reject cleared the request notification.
- A later new request generated a new notification.
- BLE helper mode continued working correctly.

These are local notifications, not remote push notifications. iOS does not use an
Android-style persistent foreground-service notification. Notification permission
denial must not disable BLE helper availability; that separation passes the native
policy tests, but denied-permission physical testing remains outstanding.

Remaining physical notification checks: foreground suppression, Disable Help Others
clearing stale alert state, and denied permission permitting BLE discovery/requests.
Process-restoration and force-quit limitations remain unvalidated.

Notification delivery depends on CoreBluetooth receiving the request and iOS
notification settings (including Focus). This adds no force-quit/process-restoration
availability guarantee and does not turn the app into a continuously running service.

The concurrent-request and Phase 1 UI checkpoint is recorded separately in
[ios-multiple-outgoing-requests.md](ios-multiple-outgoing-requests.md) and
[ios-phase-one-ui.md](ios-phase-one-ui.md). The tester confirmed physical iPhone
validation of the current combined build. Earlier detailed background/notification
results and remaining process-restoration limitations above remain distinct.
