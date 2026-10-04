# Hackathon demo runbook

Supported: **Android ↔ Android and iPhone ↔ iPhone**. Cross-platform phone chat is
excluded. The website simulation is labelled illustration, not live Bluetooth.
Use the final integration record for current evidence; no fresh physical test is
claimed by this preparation work.

## Before judging

- Install the same Android APK on two Android phones; install the separate signed
  iOS app on two iPhones. Record source SHA, APK hash and device/OS versions.
- Enable Bluetooth and permissions. Enter distinct, short names. Keep requesters
  foregrounded and the phones close. Use non-sensitive short text on iOS.
- Rehearse each same-platform flow below with Internet disconnected. Run helper
  background/notification checks before including them in the live demo.
- Serve `website/onya` using `python3 website/onya/preview.py` from the repo root.
  Keep the extracted static ZIP locally in case hosted access fails.
- Public app downloads are pending until real URLs are configured. Do not present
  unsigned iOS output as installable or the current Pages 404 as a live website.

## Two same-platform demonstrations

1. On B, enable Help Others. On A, Find Users Nearby and select B.
2. A requests; B accepts. Android waits for secure-chat readiness. iOS enters chat
   after acceptance without application-layer encryption.
3. Send “Hello from A” and “Hello from B”; point out receipt on the opposite phone.
4. Android: End → confirm. iPhone: back arrow. Verify the peer leaves the session.
5. Make a fresh connection; reject once, then reconnect and accept. Reverse roles.
6. Optional, after rehearsal: background the helper, request, tap its notification,
   accept and chat. iOS scheduling/force-quit limitations still apply.

With three iPhones, separately check multiple pending requests, first accept wins,
loser cleanup and late-event isolation. This is not multiple simultaneous chats.

## Three-minute website narration

| Time | Action | Say |
| --- | --- | --- |
| 0:00–0:25 | Hero | “onya is nearby, voluntary text chat when Internet access is unavailable. Both people install the app first.” |
| 0:25–1:10 | Find → request → reject; reset → accept → chat | “This is a browser illustration. A helper chooses to be available and approves each conversation.” |
| 1:10–1:40 | Engineering | “Separate Android and iPhone builds use native BLE, bounded frames and ACKs. We support same-platform pairs. This does not share Internet access.” |
| 1:40–2:10 | Security | “Android encrypts chat with fresh session keys, but does not authenticate identity. The preserved iPhone demo has plaintext application messages. We state those limits clearly.” |
| 2:10–2:40 | Evidence / real phone demo | “36 Android and 37 iOS Flutter tests pass, along with native Swift fixtures and iOS compilation. Builds are separate evidence from the physical tests we show.” |
| 2:40–3:00 | Installation | “Android uses a verified APK. iPhone installation requires signing or configured Apple distribution. Public links appear only when those releases actually exist.” |

If a device test fails, show the labelled simulation/local site and explain the
failure. Do not imply it proves BLE. Keep credentials and personal messages out
of recordings. Check event-specific video/submission rules before uploading.
