# OfflineRelay Android app

The current Flutter UI supports Profile, Home, Nearby, helper requests and
verified encrypted chat. Android GATT and the helper foreground service are
implemented in `android/app/src/main/kotlin/`. Other platform folders are
scaffolds with no BLE implementation.

See the repository [README](../../README.md) for commands and requirements,
[deployment audit](../../docs/testing/deployment-readiness.md) for lifecycle
limits, and [security design](../../docs/security/e2e-chat.md) for chat encryption.
The frozen `experiments/ble_poc` is independent and is not imported by this app.
