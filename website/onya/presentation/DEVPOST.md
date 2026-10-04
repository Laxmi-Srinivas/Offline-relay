# Devpost draft — Onya

Draft only. No project created, submitted or published. The specific hackathon URL
and its rules have not been supplied, so eligibility, required sponsor tools,
deadline, AI-assistance rules and video length are not verified here.

## Project name

Onya

## Tagline

No internet. A little help nearby—through a connection by choice.

## Inspiration

“I sometimes lose campus Wi-Fi while working. When I need something, I’m stuck—even
though people nearby may be able and willing to help.” That everyday moment inspired
Onya. The name comes from “good on ya”: recognizing someone who chooses to help.
Our broader goal is practical help; our first step is making a voluntary nearby
connection possible through text chat.

## What it does

Onya's committed Flutter mobile implementation supports nearby peer-to-peer text
chat over Bluetooth Low Energy. A helper makes themselves available; another person
discovers them and requests a connection. The helper accepts or rejects. Approved
peers can exchange text. Android also has background helper availability and request
notifications. The presentation website explains this flow with an explicitly
labelled browser simulation—it does not establish a Bluetooth connection.

Onya does not currently share Internet access, relay Internet traffic, automatically
order items or book rides, or implement a structured task system.

## How we built it

The mobile app uses Flutter/Dart with native Android BLE code and an existing iOS
CoreBluetooth implementation. We reviewed the actual message and approval paths
and added focused security hardening on a dedicated Security branch: consent gates,
current connection/request matching, stale-session isolation, bounded memory and
queues, recent duplicate suppression, cleanup, deadlines and notification cooldowns.

The presentation uses plain HTML, CSS and JavaScript, self-hosted typography and
original SVG artwork. Its interaction is deterministic and needs no backend,
database, accounts, analytics or external APIs. Essential assets and evidence
copies are available locally for offline judging.

## Challenges we ran into

Security fixes must preserve legitimate conversation behavior while handling
delayed approvals, reconnects and UI detachment. We also had to keep divergent
mobile branches and their evidence separate, preserve contributor history, and
avoid treating a successful build as proof of physical Bluetooth behavior.
The Android build encountered SDK setup and disk-space failures before succeeding.

## Accomplishments

Committed records substantiate 38 shared Flutter tests and analysis passing, plus
earlier Android policy tests and a successful debug APK build. Tests cover specific
consent/session/resource properties; they do not establish physical radio security.
We created a presentation that explains the human decision, engineering and
verification boundaries together rather than making unsupported security claims.

## What we learned

Discovery is not consent. A valid approval belongs to a specific conversation.
Temporary chat still needs memory limits and cleanup, and background behavior
needs its own state model. Clear, reproducible evidence is more useful than saying
an app is “fully secure.”

## What's next

The team reports the existing app was demonstrated on physical iPhones with free
Xcode Personal Team signing; that does not verify the subsequently prepared
Security changes. There is no public iOS download or supplied recording yet.

Verify prepared native iOS fixes on a Mac, complete controlled-device security
checks, establish actual Bluetooth encryption/authentication behavior, and
integrate the final mobile UI with the Security fixes before release. Peer names
are self-asserted and application-level end-to-end encryption is not established
in the inspected committed code. Add real screenshots/recordings and build links
only after the relevant implementation is verified.

## Built-with tags to confirm

Flutter, Dart, Kotlin, Bluetooth Low Energy, Swift, CoreBluetooth, HTML, CSS,
JavaScript. Swift/iOS is existing committed source with verification pending.
Do not add sponsor technologies that were not actually used.

## Links and assets

- Repository: https://github.com/Laxmi-Srinivas/Offline-relay
- Presentation URL: pending user-approved GitHub Pages deployment; do not paste localhost.
- Demo video: not yet recorded/uploaded. Follow the event's length requirements.
- Gallery cover: `../assets/devpost-cover.png`, 1200 × 800, original project
  illustration. It is not an app screenshot or evidence of device testing.
- Three-minute narration outline: RUNBOOK.md. Record the labelled website flow;
  add real app footage only if it has been captured and accurately scoped.

## Submission checks still owned by the team

- Confirm hackathon-specific eligibility, prior-work allowance, sponsor criteria,
  dates/timezone, team membership, video length and AI/tool disclosure requirements.
- Distinguish pre-existing commits from work performed during the event. Preserve
  original authorship and actual timestamps; do not claim all work began at the event.
- Review this draft for accuracy and disclosure before submission.
- Obtain approval before website publication or any submission.
- Use a public/playable demo-video link as required by the actual event; allow time
  for upload/processing and check signed-out playback.
- Complete the submission flow and confirm the final submitted state; a website
  alone does not submit the project to Devpost.

## Official guidance consulted

[Devpost submission steps](https://help.devpost.com/article/126-know-your-submission-steps)
describe the project description, links, gallery and demo-video fields and note
that additional questions vary by event. The guide recommends a 3:2 gallery
thumbnail (JPG/PNG/GIF, maximum 5 MB). The included PNG is well below that limit.
[Devpost video guidance](https://help.devpost.com/article/84-video-making-best-practices)
recommends a clear screencast and rehearsed narration. Event-specific rules take
precedence over this preparation pack.
