# Architecture

## Runtime layers

```text
MainActivity
  ├── NearbyPreflight → runtime permissions, Google Play services, radio checks
  └── ContinuityScreen ↔ ConnectionViewModel → ConnectionSession
                                           → NearbyTransport
                                           → NearbyConnectionsTransport
```

- **MainActivity** starts Compose and requests the permissions selected by `NearbyPreflight` before starting a role.
- **ContinuityScreen** displays role selection, discovery results, request details, accept/decline, chat, and end-session controls. It does not show internal HELLO diagnostics.
- **ConnectionViewModel** keeps session state across configuration changes while its process remains alive.
- **ConnectionSession** enforces role, verification, message ordering, request expiration, and chat state using platform-independent Kotlin.
- **Codecs** validate HELLO and help/chat envelopes, lengths, required fields, IDs, and timestamps before session state changes.
- **NearbyTransport** defines the app-facing transport contract. **NearbyConnectionsTransport** maps it to Google Play services Nearby Connections.

## Connection and help flow

1. A helper advertises or a requester discovers using the same service ID and point-to-point strategy.
2. The phones establish a candidate connection. Both users see and approve matching connection digits.
3. The session exchanges one internal HELLO envelope each way. It checks opposite roles and binds the session to its peers.
4. The requester sends one bounded help request. The helper may accept or decline.
5. Only after acceptance can either side send chat. Either side can end the task.

The HELLO is a protocol step, not a screen feature. The UI shows a normal connection status instead of “HELLO sent/received.”

## Boundaries

- One requester and one helper per session; direct phone-to-phone Nearby only.
- No cloud services, database, account system, booking/payment integration, background service, attachments, relay mesh, or multi-hop.
- Task and chat content stays in memory. A connection/process loss requires starting a new session.
- Protocol details and validation rules are specified in `PROTOCOL.md`.
- Privacy and security limits are specified in `SECURITY.md`.
