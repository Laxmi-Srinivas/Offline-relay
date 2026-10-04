# OfflineRelay Flutter application

Implemented Android flow: choose a name/role, discover nearby helpers, request and
approve a connection, then exchange bounded text messages over native BLE GATT.
Help Others also runs in an Android foreground service with request notifications.
The local dependency is the Dart transport contract; the app does not depend on
`experiments/ble_poc`. Chat is volatile memory only, with no database or saved history.

Android hardening is verified locally on this branch. Committed iOS native code
has now been imported for authorized security work; native fixes await Mac
verification (see ../../docs/security/IOS.md). Desktop folders are scaffolds.
No website is implemented.
See the repository [README](../../README.md),
[security findings](../../docs/security/README.md) and
[actual verification results](../../docs/security/VERIFICATION.md). Automated tests
do not establish radio confidentiality or successful notification/device behavior.
