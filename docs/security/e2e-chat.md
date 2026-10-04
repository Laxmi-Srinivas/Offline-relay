# Android chat encryption

Status: unaudited hackathon MVP implementation. Encryption setup is automatic
and requires no pre-existing trust, human code comparison, or authentication UI.

## Session setup

After the helper explicitly accepts the connection request, both Flutter
controllers create fresh ephemeral X25519 key pairs and exchange public keys
over BLE. HKDF-SHA-256 expands the shared secret into separate direction keys
for requester-to-helper and helper-to-requester traffic. The public-key pair
is hashed into the derivation salt to bind keys to this exchange.

Each phone automatically sends an AES-256-GCM encrypted key-confirmation packet.
Chat becomes ready once its confirmation has been sent and the peer confirmation
has been decrypted successfully. These are internal protocol messages: users
never see or exchange codes, keys or any other cryptographic material.
The existing accept/reject flow is unchanged. Setup has a finite timeout; failure
closes the session and allows returning to Nearby for a fresh connection.

## Message protection

Chat, key confirmation and End Chat application bodies are encrypted before BLE
transport and decrypted after receipt. AES-256-GCM authenticates ciphertext and
associated counter/direction data, detecting tampering under the established
session keys. The complete outer JSON envelope stays within 256 UTF-8 bytes.
Oversize content is rejected without truncation or automatic resend.

Each direction uses its own key and a 12-byte nonce: four zero bytes followed
by a monotonically increasing 64-bit counter in big-endian order. Fresh X25519
keys are generated for every accepted session. Encryption and sends are
serialized; counters are consumed before encryption attempts and replayed or
out-of-order authenticated counters are rejected. Keys and plaintext are not
logged or persisted, and no hardcoded shared secret is used.

## Trust and limitations

This exchange confirms possession of the derived keys, not a person's identity.
There is no authenticated identity binding, pre-shared secret, trusted directory,
certificate, pinned key, or human verification. An active man-in-the-middle can
impersonate peers and establish separate encrypted sessions with each phone.
Do not claim authenticated key exchange or protection against active peer
impersonation. Encryption protects against passive observation of chat content
and ciphertext tampering under the session keys, subject to these assumptions.

Request metadata, BLE identifiers, timing and packet lengths remain visible.
Compromised phones, screenshots and malicious recipients are outside this
protection. Messages, reports and keys are temporary Flutter memory; real engine
loss requires a new session. Dart cannot guarantee immediate key zeroization.
The implementation retains the cryptography package's standard X25519,
HKDF-SHA-256 and AES-GCM primitives, rather than adding a custom algorithm.

Report remains a local in-memory action; no moderation service receives it.
The user manually validated the automatic-encryption revision on physical
Android devices. The final branding checkpoint preserves its implementation;
Flutter analysis and all 36 Flutter tests pass. No additional physical-device
tests are performed during that checkpoint.
