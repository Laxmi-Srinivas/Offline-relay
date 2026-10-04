# Continuity judge demo

## 20-second pitch

“Continuity helps two nearby people coordinate practical help when mobile data or internet is unavailable. A requester sends a short, anonymous-by-default help request; the other person can accept or decline, then chat directly. The request and chat stay on the phones for that session. Continuity does not pretend to book services or verify real-world identity.”

## Demo setup

Run this live only after the two-phone checklist passes on the exact build being presented.

- Install the same build on two Android phones with Google Play services.
- Keep Wi-Fi and Bluetooth on; turn mobile data off on both phones.
- Grant the permissions requested by Android.
- Start with the helper phone ready to advertise and the requester phone ready to discover.
- Keep both phones awake and close together for this direct-connection prototype.

## 90-second walkthrough

1. On phone B, choose **I can help**. Explain that the helper is available without signing in.
2. On phone A, choose **I need help** and select the discovered helper.
3. Complete the displayed connection verification on both phones. Explain that this confirms the device-to-device session; it does not prove someone’s real-world identity.
4. On A, choose **Food** and send a short request such as “I need help figuring out how to get dinner.”
5. On B, show that the request can be accepted or declined. Accept it.
6. Send one chat message from each phone, then end the session. Point out that no payment or order was made and the chat is temporary.

## What to say about the design

- **Why offline:** the help request and chat use a direct Nearby connection instead of a server. Mobile data and internet are not used for the live phone-to-phone session.
- **Why anonymous-by-default:** the app uses requester/helper roles and does not ask for names or accounts. The helper sees the text the requester chooses to send, so the requester should share only what is needed.
- **What “verified” means:** both phones confirm the connection code before Continuity exchanges its session hello and enables help messages. This is connection verification, not identity verification.
- **Why the scope is small:** the prototype proves one requester, one helper, one request, and one temporary chat. It does not place orders, process payments, dispatch emergencies, relay through strangers, or resume after disconnection.

## Likely judge questions

**Can it reach someone on another floor or across a large crowd?**

The current implementation connects two nearby phones directly. It has no relay mesh or multi-hop delivery, so it cannot promise that range.

**How do you know the helper is safe?**

Continuity does not verify real-world identity or certify helpers. It verifies the phone connection and makes the requester choose what to disclose. This is a prototype limitation, not a solved safety guarantee.

**Does it order a ride or food?**

No. It lets two people coordinate by text; they would use any separate service themselves.

**Does it store the conversation?**

The current app keeps request and chat data in memory for the active session. It has no account or conversation history feature.

**What did you test?**

Describe only the checks recorded in `BUILD-VERIFICATION.md` and the device checklist. A successful build and unit tests do not prove nearby radio behavior.

## Demo integrity

Never present a planned step as a tested result. If the live connection fails, show the actual current limitation and the build/device evidence; do not imply the task/chat flow was completed on phones unless it was.
