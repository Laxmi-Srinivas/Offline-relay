# onya hackathon architecture

Supported paths: Android ? Android and iPhone ? iPhone. Cross-platform phone
communication is excluded. The website provides installation guidance; it does
not connect to BLE or relay chat.

```text
Android Flutter UI/controller             iPhone Flutter UI/controller
  apps/offline_relay                        apps/offline_relay_ios
       |                                         |
Encrypted Relay envelopes                Existing plaintext Relay envelopes
  packages/relay_transport                 packages/relay_transport_ios
       |                                         |
MethodChannel / EventChannel             MethodChannel / EventChannel
       |                                         |
Kotlin GATT + foreground helper           Swift CoreBluetooth + helper owner
       |                                         |
another Android                          another iPhone
```

Both protocols bound complete envelopes to 256 bytes. Native adapters fragment
them into 16-byte payloads with a 4-byte header, reassemble and acknowledge whole
messages. Historical UUIDs are unchanged; they do not establish app compatibility.

Android comes from `cf59a02`; iPhone comes from `ios-mvp` at `4cf4865`.
The iOS copy uses an isolated path dependency so Android protocol changes cannot
alter its validated decoder. Internal package names, IDs and native namespaces
remain unchanged. This is an integration boundary, not a networking rewrite.

Android retains X25519/HKDF/AES-GCM, encrypted chat/End Chat, local Report and
foreground helper notifications. iOS retains acceptance, concurrent requester
selection, plaintext chat, disconnect-on-back, background helper availability
and local notifications. No iOS app encryption or Report feature is claimed.

The existing website layout and interaction are reused with corrected scope and
security claims. Deployment packages only public static files. The frozen POC,
interop adapter and native Android replacement are excluded from final app
integration. See [verification](../testing/final-integration.md).
