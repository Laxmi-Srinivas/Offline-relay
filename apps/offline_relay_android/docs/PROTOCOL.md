# Continuity shared protocol — Android P0

Status: implementation source of truth for the offline request/chat slice. Owner: Anand (solo).

Continuity directly connects two nearby Android phones using Google Nearby Connections. The app connection and its messages do not require internet or mobile data; Wi-Fi and Bluetooth remain enabled. There is no cloud account or real-world identity check.

## 1. User flow

DISCOVER → CONNECT → HELLO → REQUEST → ACCEPT or DECLINE → CHAT → END → TEST

The helper may coordinate a real-world task in chat. Continuity does not place orders, book rides, handle payments, or use another person's account. There is no mesh or multi-hop relay.

## 2. Peer model

The transport exposes a discovered `endpointId` and `displayName`. `endpointId` is only a Nearby routing value. After verified connection, each peer sends a HELLO with a random session `peerId` (UUID v4), a generic display label (`Requester` or `Helper`), and role (`REQUESTER` or `HELPER`). The peer ID is bound to that connection only; it is not a real-world identity and is cleared when the connection ends.

One connected peer and one help task per session. Roles are selected before connection and must be complementary.

## 3. Task model

| Field | Type / allowed value | Purpose |
| --- | --- | --- |
| taskId | UUID v4 | Identifies this request and binds its chat |
| category | `FOOD`, `RIDE`, or `OTHER` | Broad kind of requested help |
| details | Nonblank UTF-8 text, 1–500 bytes | Requester explains what help is needed |
| createdAt | Positive Unix epoch milliseconds | Request creation time |
| expiresAt | `createdAt + 300000` | Five-minute task lifetime |

Details are visible to the connected helper. No separate name, address, phone, account, or payment fields are defined. Users may include needed details in the request/chat; the UI warns not to send passwords or payment credentials. The task is immutable after send.

## 4. Message envelope and types

Each byte payload is one UTF-8 JSON object, maximum 8192 encoded bytes. Exact case-sensitive field names; reject duplicate keys, unknown fields, invalid UTF-8, invalid values, and trailing data. IDs are lowercase canonical UUID v4 strings. Timestamps are 64-bit Unix epoch milliseconds. Task messages copy the request's original task timestamps.

Common task-message fields: `version` (integer `1`), `messageId` (fresh UUID), `taskId`, `createdAt`, `expiresAt`, `type`, and `payload`. HELLO uses the same envelope without `taskId`; its `expiresAt` is `createdAt + 30000`.

| Type | Direction and guard | Payload |
| --- | --- | --- |
| HELLO | Both peers after verified transport connection | `peerId`, `displayName`, `role` |
| TASK_REQUEST | REQUESTER → HELPER; both READY | `category`, `details` |
| TASK_ACCEPT | HELPER → REQUESTER; request pending | Empty object |
| TASK_DECLINE | HELPER → REQUESTER; request pending | Empty object |
| CHAT_MESSAGE | Either peer; only after acceptance | `text`: nonblank UTF-8, 1–1000 bytes |
| TASK_END | Either peer; only after acceptance | Empty object |

No separate result payload is sent. The helper reports the outcome in chat; either peer can end the task. Every message has a distinct messageId. An exact duplicate is ignored; reuse of an ID with different bytes is invalid.

## 5. Task states and transitions

Local state values: `REQUESTED`, `ACCEPTED`, `DECLINED`, `ENDED`, `FAILED`, `EXPIRED`.

| Current | Event | Next |
| --- | --- | --- |
| No task / READY requester | Valid request submitted and sent | REQUESTED |
| READY helper | Valid request received | REQUESTED |
| REQUESTED helper | Accept | ACCEPTED; chat opens |
| REQUESTED helper | Decline | DECLINED |
| REQUESTED requester | Accept received | ACCEPTED; chat opens |
| REQUESTED requester | Decline received | DECLINED |
| ACCEPTED | Valid chat message | ACCEPTED |
| ACCEPTED | TASK_END from either peer | ENDED |
| Active task | Connection loss or send failure | FAILED |
| Active task | Five-minute deadline reached | EXPIRED |

Reject chat before acceptance, task messages from the wrong role/connection, mismatched task IDs/timestamps, and all transitions not listed above. A declined/ended/failed/expired task cannot be resumed.

## 6. Accidental exit and reconnection

Android Back during chat prompts the user. Choosing Keep chatting leaves the task open; choosing End Help sends TASK_END. Backgrounding or rotation does not end the task while the Android process and Nearby connection remain alive. Chat history is in memory only. If Android kills the process or the Nearby connection is lost, both peers must establish a new verified session; automatic reconnection or task restoration is not implemented.

## 7. Nearby transport boundary

`NearbyTransport` carries bounded bytes and connection events. It does not interpret task content. Only send after HELLO completes on both phones. Payloads must be BYTES and no larger than 8192. One point-to-point endpoint per session. Stop discovery/advertising and disconnect on explicit session stop or connection failure. Task state and chat never use a server.

## 8. Validation and error behavior

- Decode UTF-8 strictly and enforce the exact envelope/payload keys and limits above.
- Require the verified endpoint and bound complementary peer role for every message.
- Require a matching active task and original task timestamps on every post-request message.
- Allow CHAT_MESSAGE and TASK_END only after TASK_ACCEPT.
- Require nonblank request/chat text; count UTF-8 bytes, not Kotlin characters.
- Keep request/chat content and duplicate-message IDs in memory for this connection only; cap distinct task-session message IDs at 128.
- Reject invalid input without crashing. On invalid protocol state or connection/send failure, close the session and show a clear error; do not silently perform an action.

Known product boundary: categories help organize requests but do not make an order or ride safe, available, or completed. The requester and helper coordinate manually. The helper can see all submitted details; Continuity does not verify either person's real identity.
