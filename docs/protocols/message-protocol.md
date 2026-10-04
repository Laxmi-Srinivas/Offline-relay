# Message protocol: experimental requirements

Status: common application protocol remains design notes. The experiment-local
format below is implemented in native Android source, not yet build/device verified.

## Future common application envelope

Expect a version, message identifier, message type, and bounded payload. Peer
identifiers must not depend on Bluetooth MAC addresses or IP addresses. Encoding,
limits, compatibility negotiation, and error schema remain undecided.

## Throwaway BLE exchange

Start with UTF-8 `Hello` (5 bytes), then a deterministic 256-byte payload to
exercise fragmentation. The receiver compares exact reassembled bytes against
these two allowed vectors; the sender checks the ACK ID and total length. The
experiment uses the UUIDs and frame layout in its [runbook](../../experiments/ble_poc/README.md).
Frames contain message ID, sequence, and count. Frame lengths delimit payload;
the final ACK includes the reassembled length. Invalid sequence/length and
oversize messages are rejected.

Only send an application ACK referencing the message ID after complete receipt
and validation. A GATT write response is not this ACK. Log successful sending
only after the relevant callback; log acknowledged delivery only after matching
the application ACK. Enforce finite connection, discovery, send, reassembly,
and ACK timeouts. Clear pending state on disconnect. No automatic retries or
exactly-once-delivery claims are required for the first experiment.

The larger payload and ACK remain unverified physical-device acceptance
criteria. Source code and passing Flutter tests do not establish BLE delivery.
