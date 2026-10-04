# Onya two-minute live demo

| Time | Show | Say |
| --- | --- | --- |
| 0:00–0:20 | Opening and origin story | “I sometimes lose campus Wi-Fi while working and can’t finish an online task. People nearby may be willing to help, but it’s hard to find them. Onya starts with that everyday problem.” |
| 0:20–0:40 | Requester/helper journey | “A nearby helper chooses to be available. Someone requests a connection. The helper accepts or rejects, and only acceptance opens chat. Onya makes the connection; any practical help happens manually outside the app.” |
| 0:40–1:00 | Simulation: request, reject, reset, accept, show chat | “This is an illustrative browser simulation, not Bluetooth. Discovery isn’t consent. Jamie can decline, or accept and then chat. The example shows a small ask for help finding the campus desk.” |
| 1:00–1:25 | BLE diagram and security | “Flutter runs the app interface; native Android code handles Bluetooth Low Energy. Security source encrypts approved chat, bounds memory and isolates sessions. Its key exchange doesn’t authenticate the peer, so we don’t claim verified identity or active-meddler protection.” |
| 1:25–1:50 | Evidence and download | “The record shows 60 shared Flutter tests and analysis passing. Two phones passed foreground approval, chat and fresh-session checks on the Security source. Background delivery and rejection still fail. The Onya APK is debug-signed and not device-retested. We planned iOS-to-iOS integration, but a failed merge and debugging used the submission time; it remains unfinished.” |
| 1:50–2:00 | Close | “That integration isn’t part of this Android demo. Next, we’ll measure request-to-accept time, successful approved chats and comfort with discovery. Someone nearby can choose to help.” |

## Before presenting

- Open the deployed site once while online and confirm the Android APK release link works.
- For an offline talk, extract the local ZIP and open `index.html`. Pre-download the APK if you need to show the file; GitHub downloads require Internet.
- Do not call the browser simulation a device demo. No real recording is embedded.
- The APK is a 0.0.1 debug-signed Android test build, about 149 MiB. Both nearby participants need the same build; Android 12 or newer is required.
- Do not claim Bluetooth link authentication, verified peer identity, production readiness, or successful background-chat/rejection behavior.
- Keep the live presentation to two minutes and leave questions for afterward.

## Local preview

Run `python website/onya/serve.py` from the repository root and open the printed local address. Website assets are local; APK download points to GitHub and requires Internet. `python website/onya/package_site.py --output <path-outside-repository>/onya.zip` creates the static fallback.
