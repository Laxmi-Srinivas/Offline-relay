# Reproducible verification

## Automated checks

Consent/session changes: Flutter analysis passed, all 19 tests passed (9 existing
and 10 new regressions). The 10 new tests first failed on the unchanged controller,
then passed after the fix. See COMMANDS.md for actual commands and tool setup.
Native, memory-policy and device checks below remain pending at this checkpoint.

Using matching Flutter 3.47.6 / Dart 3.13.5, from `apps/offline_relay`:

```text
flutter pub get
flutter analyze
flutter test
```

Consent/state regression tests must cover missing request IDs, pre-approval chat,
duplicate control messages, request replacement, disconnect/reconnect, stale
async completions, and correct normal approval/send/receive behavior.
Native deadline tests must use controlled time and exercise the production timer
helper, including send/receive overlap, receive completion and stale timer callbacks.
Compiler/helper checks do not substitute for a full APK build or device tests.

## Physical-device checks (not run)

Only use owned/authorized phones and non-sensitive test messages. A deliberately
modified local test peer may send invalid envelopes/frames; never scan or probe
unrelated devices or services.

1. Offer Help / Find Nearby, request, accept/reject and bidirectional chat.
2. Before acceptance send chat and accept with no request ID: no chat transition
   or history entry. After valid approval, normal messages still work.
3. Hold an idle incoming BLE link without subscribing; verify setup expiry.
   Subscribe but send no application request; verify request expiry and recovery.
4. Start a send, deliver inbound traffic and withhold ACK. Send must fail at its
   own deadline despite receive success/failure; legitimate duplex transfers work.
5. Disconnect mid-frame/mid-send, background, restart and reconnect to a different
   peer. No old history, request or late callback changes the new conversation.
6. Reject malformed/oversize/out-of-order frames and invalid UTF-8/JSON. Check
   byte boundaries with Unicode as well as ASCII (160 UI characters is not 256 bytes).
7. Repeat complete envelopes and run a controlled valid-message burst; record
   memory/responsiveness and the agreed history policy before claiming flood resistance.
8. Inspect link security on freshly unpaired phones with an authorized local
   Bluetooth capture/log method. Record pairing method, encryption and authenticated
   protection; do not infer it from ACKs or bond status. No transport-security change
   is included before verifying the gap and agreeing pairing behavior.
9. Inspect product system logs, app files/preferences/caches and backups for the
   synthetic message and test identifiers. Do not share raw device identifiers.

## Remaining limitations

Radio encryption/integrity, callback ordering, GATT duplex scheduling, device
teardown and actual resource exhaustion are not established by source inspection.
No database, web or helper service is implemented. iOS changes and cross-platform
compatibility are deferred. Release uses the scaffold debug signing configuration;
production distribution requires a separate signing plan.
