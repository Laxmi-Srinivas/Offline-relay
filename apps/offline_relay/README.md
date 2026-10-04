# OfflineRelay MVP host

Nearby Users / connection approval / peer chat product flow is synchronized with
main commit `e402922d80f9830bce08a752dc8a1e05a895bd30`. Shared Dart code stays
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
do not commit signing settings or generated build output. Foreground operation only.
