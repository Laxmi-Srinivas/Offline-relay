# Three-minute presentation

Use the website as the presentation. Keep the simulation label visible. This is
an illustrative flow; no real-device capture is available in this handoff.
Both nearby users need the app installed beforehand. Do not imply that
Android–iPhone interoperability was verified. The team reports a physical iPhone
app demonstration with Personal Team signing; our native Security changes still
need their own checks. The exact demonstrated iPhone build SHA was not supplied.

| Time | Page / action | Speaking script |
| --- | --- | --- |
| 0:00–0:20 | Opening | “I sometimes lose campus Wi-Fi while working. When I need help, I can feel stuck—even with people right beside me. Onya is a nearby text-chat app that lets someone choose to help. The name comes from ‘good on ya’: recognizing that small decision.” |
| 0:20–0:40 | The idea | “Our bigger motivation is practical help. What we’ve implemented today is the connection: a helper becomes available, another person discovers them and requests a connection. The helper accepts or rejects. Chat follows acceptance.” |
| 0:40–1:25 | Simulation: Find → Request → Reject; reset; Find → Request → Accept → Show chat | “This is a labelled browser simulation, not live Bluetooth. Alex finds Jamie, then asks to connect. Discovery isn’t consent. Jamie can decline, and no chat opens. Let’s reset and accept instead. Now the two can exchange text—for example, asking where the campus help desk is.” |
| 1:25–1:50 | Engineering | “The app uses Flutter with native Bluetooth Low Energy adapters. Text moves directly between nearby devices in bounded message frames. This does not give the requester Internet access, and it doesn’t automatically place orders or book rides. Android also has helper availability and request notifications through a foreground service.” |
| 1:50–2:20 | Security | “We focused on the implemented path: approval before chat, matching decisions to the current connection, and keeping old session events out of new conversations. We bounded memory and queued work, suppressed recent duplicates, cleaned up chat and drafts, and added timeouts and notification cooldowns.” |
| 2:20–2:45 | Evidence | “Our committed reports record 38 shared Flutter tests and analysis passing, plus earlier Android policy tests and a debug APK build. These are scoped results, not physical radio-security proof. iOS native fixes still need Mac verification. Bluetooth encryption and authentication remain unverified; we aren’t claiming end-to-end encryption.” |
| 2:45–3:00 | Close | “Security fixes and the newer mobile UI still need final integration and device checks. But the idea is simple: someone nearby can choose to make your day easier. Good on ya.” |

Rehearse at your natural pace and shorten if needed. The hackathon's permitted
demo-video duration may differ; use its rules, not this script's three-minute target.

## Pre-demo checklist

- [ ] Start `python preview.py`; open http://127.0.0.1:4173/ in Chrome/Edge.
- [ ] Check the actual presentation screen at comfortable zoom; close unrelated tabs.
- [ ] Reset the simulation; test accept, reject and reset once; return to the top.
- [ ] Keep the ZIP extracted locally as fallback; open index.html once offline.
- [ ] Know that GitHub links need Internet; use included local evidence reports offline.
- [ ] Confirm status matches the presented source commits; do not replace pending
      results with planned outcomes or imply newer UI is covered by the older APK.
- [ ] Keep personal information and credentials out of screen capture.
- [ ] Use the original cover as a project illustration, not app/device evidence.
- [ ] Rehearse the full flow once; have a second teammate watch the timing if available.
- [ ] For Devpost, check event-specific rules, video duration and required fields;
      verify video playback and submitted links from a signed-out browser after publication.

## If something fails during judging

Use the local extracted site. If JavaScript is disabled, walk through the static
journey and the written fallback flow. Do not improvise a successful physical
device demonstration or an encryption claim. A device demo can be added only after
it is actually captured and labelled with its source/build.
