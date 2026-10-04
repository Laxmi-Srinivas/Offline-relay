# Onya two-minute live demo

## Speaking and click-through script

| Time | Show | Say |
| --- | --- | --- |
| 0:00–0:20 | Opening headline and origin story | “I sometimes lose campus Wi-Fi while working and can’t finish an online task. People nearby may be able and willing to help, but it’s hard to find them. Onya starts with that small, familiar problem.” |
| 0:20–0:45 | Three-step requester/helper journey | “A nearby helper chooses to be available. Someone requests a connection. The helper accepts or rejects; only acceptance opens a conversation. Onya supports the first connection, while any practical action happens manually outside the app.” |
| 0:45–1:05 | Browser simulation: request, reject, reset, accept, show chat | “This is an illustrative browser simulation, not Bluetooth. It makes consent visible: discovery is not approval. After acceptance, the example chat shows the kind of small ask Onya can carry.” |
| 1:05–1:30 | BLE diagram and security section | “The app is Flutter with native Android Bluetooth adapters. Approved chat messages are encrypted in the Android Security source. The key exchange does not authenticate the peer, so we do not claim authenticated identity or protection from active key substitution. Session and memory boundaries are tested in shared code.” |
| 1:30–1:50 | Evidence and Android test-build panel | “The committed record reports 60 shared Flutter tests and analysis passing. Two owned phones completed foreground approval, synthetic chat and fresh-session checks on the Security source. The downloadable Onya APK is a debug-signed rebuild and has not itself been retested on phones. Background chat delivery failed and rejection showed a Bluetooth error.” |
| 1:50–2:00 | Close | “Our next step is a small campus worker and student pilot. We’ll measure request-to-accept time, successful approved conversations and comfort with discovery. Someone nearby can choose to make your day easier.” |

## Before presenting

- Open the deployed site once while online and confirm the Android APK release link works.
- For an offline talk, open the extracted local website ZIP. Pre-download the APK too if the demo needs to show the file; GitHub downloads require Internet.
- Do not call the browser simulation a device demo. No supplied device recording is embedded.
- The APK is a 0.0.1 debug-signed Android test build, about 149 MiB. Both nearby participants need the same test build; Android 12 or newer is required.
- Do not claim Bluetooth link authentication, authenticated peer identity, production readiness, or successful background chat/rejection.
- Keep the interactive presentation within two minutes; leave judge questions for afterward.

## Local preview

Run `python website/onya/serve.py` from the repository root, then open the printed local address. The site and assets are local; the APK download points to GitHub and requires Internet. `python website/onya/package_site.py --output <path-outside-repository>/onya.zip` creates the static presentation fallback.
