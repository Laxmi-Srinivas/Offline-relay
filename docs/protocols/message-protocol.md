# OfflineRelay application message protocol

Version 1 uses the shared JSON envelope in
`packages/relay_transport/lib/relay_transport.dart`:

```json
{"version":1,"id":"...","type":"...","body":{}}
```

The complete UTF-8 encoding must fit the existing 256-byte transport limit.
Android GATT owns fragmentation, reassembly and transport ACKs. Encryption runs
above this boundary; BLE carries ciphertext for chat content.

## Request and automatic encrypted session flow

1. The requester sends `connection_request` with its display name and role.
2. The helper explicitly sends `connection_accept` or `connection_reject`.
   The requester can send `connection_cancel` while waiting.
3. After acceptance, both peers automatically exchange fresh ephemeral X25519
   public keys in `key_exchange` envelopes and derive directional session keys
   with HKDF-SHA-256.
4. Both automatically send encrypted `key_confirmation` application packets.
   Once both confirmations complete, chat is ready. There is no displayed code,
   human confirmation or extra authentication screen.
5. `secure_message` carries a monotonically increasing counter and base64url
   ciphertext plus its AES-256-GCM authentication tag. The encrypted content
   includes the application type/body for `chat`, `key_confirmation` or `end_chat`.

Plaintext chat and key-confirmation envelopes are ignored. Connection metadata
and ephemeral public keys are not encrypted because they precede session setup.
Setup confirms keys but does not authenticate peer identity or prevent active
man-in-the-middle impersonation. See [encryption design](../security/e2e-chat.md).

Requests expire after 60 seconds; automatic encryption setup has a two-minute
maximum. Sends are serialized and never silently retried. Failed/oversized sends
preserve the draft. Ending a chat waits for its final inbound transport ACK before
native cleanup. Transport ACK does not mean the peer user read the message.

Service request/response types are reserved; the MVP does not expose them.
The frozen [BLE POC](../../experiments/ble_poc/README.md) retains its validated
UUIDs and framing as an independent diagnostic reference and is unchanged.
