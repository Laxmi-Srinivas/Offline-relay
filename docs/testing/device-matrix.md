# Device matrix and acceptance evidence

Historical BLE POC and product transport tests passed on OPPO CPH2729 and
Realme RMX3998IN, Android 16 / API 36; see [validation history](validation.md).
Current deployment-stage UI/chat/lifecycle evidence is recorded in
[deployment-readiness](deployment-readiness.md). A build or mock test is not
physical BLE evidence.

| Target | Evidence / support boundary |
| --- | --- |
| OPPO CPH2729 / Realme RMX3998IN | Physical Android 16 BLE reference pair; current stage recorded separately |
| Other Android 12+ hardware | Not tested; peripheral advertising and OEM service behavior vary |
| Android 12 / 13 / 14 / 15 | Supported API minimum does not establish physical validation |
| Android / iOS or iOS / iOS | No current iOS BLE adapter; not tested |
| Desktop LAN / phone-to-laptop | Not implemented or tested |

For a fresh physical run, install the same current APK on both phones and record
revision, OS, roles, permissions and results. Test background helper discovery,
notification/open/accept, automatic encrypted setup, bidirectional
chat, report/end, reject/cancel, reconnect, rotate, Bluetooth off/on, permission
denial/revocation, Activity/engine loss, process kill/force-stop, peer departure,
and timeout/malformed/fragmented transfer behavior. Swap roles when possible.
Keep test strings nonsensitive and do not publish raw device logs or identifiers.
