# OfflineRelay Flutter application

Implemented Android flow: choose a name/role, discover nearby helpers, request and
approve a connection, then exchange bounded text messages over native BLE GATT.
Help Others also runs in an Android foreground service with request notifications.
The local dependency is the Dart transport contract; the app does not depend on
`experiments/ble_poc`. Chat is volatile memory only, with no database or saved history.

Android is the security workstream on this branch. iOS code is on a separate branch
and deferred; desktop folders here are scaffolds. No website is implemented.
See the repository [README](../../README.md),
[security findings](../../docs/security/README.md) and
[actual verification results](../../docs/security/VERIFICATION.md). Automated tests
do not establish radio confidentiality or successful notification/device behavior.
