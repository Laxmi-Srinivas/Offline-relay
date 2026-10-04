# OfflineRelay MVP host

Home / Nearby / Profile and chat UI is adapted from main commit
`67acd0632eb1965482d7b745e06f1ef0c83b55f5`. The iOS controller retains multiple
pending outgoing requests and first-accept-wins behavior instead of main's single
outgoing request assumption. Shared Dart code stays
platform-neutral. On `ios-mvp`, native CoreBluetooth implements both roles in
`ios/Runner`; Android implementation files remain at this branch's prior checkpoint.

This product app is separate from the physically validated disposable reference
in `experiments/ble_poc`. The product iOS adapter has passing analysis/tests and
simulator compilation. The user reported successful real-app two-iPhone discovery,
connection approval, and bidirectional chat in both role assignments. See the
validation record for tested scope and remaining failure cases.

See [the iOS product adapter record](../../docs/testing/ios-product-adapter.md)
for channel contracts, profile discovery, platform differences, and device steps.
Use a local signing Team for bundle identifier `dev.offlinerelay.offlineRelay`;
do not commit signing settings or generated build output.

The helper-availability implementation adds Enable/Disable Help Others,
peripheral background mode, and conditional CoreBluetooth restoration. Offline User
central sessions remain foreground-only. Background availability is OS-controlled
and has passed two-iPhone background discovery, pending-request replay, Accept/chat,
Reject retention, and reconnect tests. Process restoration and force-quit behavior
remain unvalidated. See [the helper availability record](../../docs/testing/ios-helper-availability.md)
for supported behavior, platform limits, test results, and required device checks.

See [the Phase 1 UI record](../../docs/testing/ios-phase-one-ui.md) for UI adaptations,
preserved native behavior, automated checks, physical iPhone validation confirmation,
and the three-iPhone regression checklist.
