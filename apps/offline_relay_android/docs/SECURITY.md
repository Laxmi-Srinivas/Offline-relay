# Security and privacy boundaries

## Data handled

- No account, password, real-name profile, or cloud backend is used.
- Request text and chat text are sent only over the active Nearby connection and kept in session memory.
- The connected helper can read the requester’s selected category and request details. The app warns users not to send passwords, payment credentials, or other secrets.
- Closing the session or losing its process/connection does not restore its chat. Persistent history, export, and attachments are not implemented.

## Connection checks

- Android Nearby provides a connection authentication code. Both users must compare and approve it before the app exchanges its protocol HELLO.
- HELLO binds an ephemeral peer identifier and role to the session. It blocks same-role pairing and gates help messages to the active verified connection.
- The code check verifies the device connection. It does **not** verify the person’s real-world identity or guarantee that a helper is safe.
- Session IDs and generic role names are pseudonymous identifiers, not account authentication.

## Message validation

`PROTOCOL.md` is the source of truth for schemas and limits. The Kotlin codecs reject malformed or unexpected envelopes, invalid UTF-8, invalid IDs/roles/state, oversized text, and expired messages. Chat is enabled only after an accepted request. Tests cover codec and session behavior with fake transports; they do not prove radio security or physical-device delivery.

## Android permissions

The app declares Wi-Fi, Bluetooth, location, and Nearby Wi-Fi permissions needed by the current Nearby implementation. `NearbyPreflight` requests permissions at runtime and checks Google Play services and radios. The source currently declares coarse and fine location without an SDK cap because recent device runs reported distinct Nearby missing-permission errors. The permission behavior must be retested on the actual Oppo and Realme builds before release.

The app does not call Android location APIs to read coordinates, and no coordinates are part of the request/chat protocol. Android may still show a location permission prompt because the Nearby library/platform requires the permission in some configurations.

## Known limits

- No identity verification, moderation, abuse reporting, trust/reputation system, emergency dispatch, delivery/ride booking, or payment handling.
- No relay mesh, multi-hop, server fallback, or long-distance guarantee. Phones must be nearby and running the app.
- The current two-phone Nearby request/chat flow has not completed physical-device acceptance testing. See `BUILD-VERIFICATION.md`.
