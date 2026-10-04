# OfflineRelay current MVP scope

OfflineRelay connects a nearby requester with a willing helper for temporary
Bluetooth LE chat without sharing or tunnelling an Internet connection.

The current Android demo implements Flutter Home/Nearby/Profile/chat screens,
helper availability in a foreground service, normal request notifications,
accept/decline/cancel, short encrypted chat, End Chat and local in-memory Report.
Encryption setup is automatic after acceptance, with no human verification.
Peer identity and active man-in-the-middle protection are not provided. No service-request execution,
Internet availability verification, backend, accounts, persistence, moderation,
automatic reconnect or LAN adapter is implemented.

Android BLE requires API 31+ and peripheral advertising support on the helper.
The iOS/desktop folders remain scaffolds without this adapter. The independent
BLE POC is frozen and its historical physical evidence is preserved.

See [deployment audit](../testing/deployment-readiness.md),
[architecture](../architecture/overview.md),
[protocol](../protocols/message-protocol.md), and
[device validation](../testing/validation.md) for actual behavior and limits.
