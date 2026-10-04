# Android phone test guide

Use Android 12 or newer and phones you own/have permission to test. A second
BLE-capable phone running the same Security app is needed for real peer chat.
The emulator is not a substitute for this radio/notification verification.

## Install

1. Obtain the debug APK built from the recorded Security commit. It is a local
   test build, not a production release. Do not put credentials or private chat in it.
2. Connect your phone by USB; enable Developer options/USB debugging and approve
   this computer. [Official Android device setup](https://developer.android.com/studio/run/device).
3. From Android platform-tools, run `adb devices`; the intended phone must be
   listed as `device`, not `unauthorized` or `offline`.
4. Install with `adb -d install -r <path-to-app-debug.apk>` (one physical phone).
   With multiple phones use `adb -s <your-phone-serial> install -r <apk>` explicitly.
   If Android rejects a different signing key, stop: do not uninstall/discard an
   existing app's data automatically.
5. Open OfflineRelay; enable Bluetooth and approve Nearby Devices and notification
   permissions when prompted. The app's Android manifest requires Android 12+.

APK output after a successful build, relative to `apps/offline_relay`:
`build/app/outputs/flutter-apk/app-debug.apk`. Do not commit the binary to source Git.
Alternative: copy that APK to your phone and open it using your file manager;
Android may require install permission for that specific file manager.

## First test (two controlled phones)

1. Phone A: name `Helper A`, choose Internet Helper, tap Enable Help Others.
   Expect an ongoing availability notification. Put the app in the background.
2. Phone B: name `Test B`, choose Offline User, tap Find Nearby Helpers, then
   Connect to Helper A. Expect a request notification on A; tap it to return to UI.
3. Before A accepts, B must remain waiting. Accept on A, exchange short synthetic
   messages in both directions, and verify they appear under the correct peer.
4. Disconnect/end the conversation. Reconnect and reject this time: chat must stay
   unavailable and helper availability should recover. No old message/draft should
   appear in a different conversation.
5. During an approved conversation background A, send messages from B, then return
   to A. Same-live-session chat should remain usable. End the connection while A is
   backgrounded, then return: the old chat must not remain approved.
6. Tap Disable Help Others when available. Confirm the ongoing notification/service
   stops and the phone no longer offers that helper connection.

Record Android models/versions, permission states, source commit, each expected vs
actual result, and failures. A notification suppressed by the 10-second cooldown
does not remove the request from the app. Record lock-screen disclosure separately.

This normal-flow check does not prove encryption, tamper resistance or flooding
protection. Malformed/repeated/stale-event tests and freshly unpaired link-security
checks are described in [VERIFICATION.md](VERIFICATION.md). Only controlled local
test peers may send deliberately invalid traffic; never probe unrelated phones.
