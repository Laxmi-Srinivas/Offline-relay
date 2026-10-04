# Two-phone acceptance checklist

Use this after both phones are available. Run the same source/build on both phones. Android Studio’s **Run** action installs directly to the selected USB-connected device; a separate APK copy is not required.

## Prepare

1. Connect both phones to Android Studio with USB debugging authorized.
2. Press **Run** once for each phone to install/update the app.
3. Keep Wi-Fi and Bluetooth on. Turn mobile data off on both phones.
4. Allow the requested Nearby and location permissions. On newer Android versions, verify the app’s permission page if a required permission was already denied.
5. Keep the apps open and phones close together; this build has direct, nearby discovery only.

## Test the complete flow

1. On phone B, tap **I can help** and leave the screen open.
2. On phone A, tap **I need help** and wait for phone B to appear.
3. Connect and compare the displayed verification digits on both phones. Confirm only when they match.
4. Confirm both screens show a normal connected/ready state. HELLO protocol details are intentionally hidden from the UI.
5. On A, send a short FOOD request. Confirm it appears on B.
6. On B, accept. Confirm both enter the chat.
7. Send a message from each phone and confirm delivery in both directions.
8. Press Android Back during chat, choose **Keep chatting**, and verify chat remains open.
9. End help from one phone. Confirm the session ends on both and chat is no longer available.
10. Repeat once with **Decline** and once with RIDE or OTHER.

## Record the result

- Build version installed:
- Device model / Android version / target role:
- Mobile data off on both:
- Both discovered and connected:
- Verification accepted on both:
- Request reached helper:
- Accept and decline behavior:
- Messages delivered both ways:
- Back / Keep chatting:
- End help on both:
- Error text and which device:

## Current known issue

Earlier screenshots showed the Oppo reaching READY while the Realme reported Nearby `8033: MISSING_PERMISSION_CHANGE_WIFI_STATE`. The manifest declaration was corrected in v0.3.2. Subsequent location permission edits and the v0.3.3 candidate still require a fresh build and Realme test. Do not mark the full device flow as passed until the checklist above succeeds on the same build.
