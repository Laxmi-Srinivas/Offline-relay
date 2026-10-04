# Onya presentation

One responsive presentation page, a small evidence appendix and a deterministic
two-phone illustration. Plain HTML/CSS/JavaScript, self-hosted Manrope/Inter (OFL
licenses included) and original SVG artwork. No package manager, build installation, real
Bluetooth, backend, database, tracking, remote font or external API.

## Preview now

From this folder:

```sh
python preview.py
```

Open **http://127.0.0.1:4173/**. The server binds only to this computer. It serves
the site folder, not the repository root. Python 3 is the only preview prerequisite.
Use `python preview.py --port 4174` if the default port is occupied.
Stop with Ctrl+C. No Internet connection is needed after obtaining the files.

Fallback without Python: open `index.html` directly in Chrome or Edge. The
simulation, SVGs, CSS and local reports work over file://; the browser may use a
system font because of local-file font restrictions. Use the local HTTP preview
for the most consistent typography. GitHub links require Internet; local evidence
copies are available beside them. No service worker/cache is required.

## Story and presentation materials

- [Three-minute script and pre-demo checklist](presentation/RUNBOOK.md)
- [Devpost draft and submission checklist](presentation/DEVPOST.md)
- [Verification results, commands and limitations](VERIFICATION.md)
- [Deployment and installation steps](DEPLOYMENT.md)
- [Source hashes and commits](evidence/sources.json)
- [Devpost cover, 1200 × 800 PNG](assets/devpost-cover.png): project illustration,
  not an app screenshot. Editable source: `presentation/cover.html` / `cover.css`.

Deployment target: GitHub Pages. The workflow packages only public website files
and publishes reviewed website changes pushed to `integration/final-hackathon`.
No publication was performed during this verification. Pages is configured, but
the expected public URL currently returns 404. See DEPLOYMENT.md before pushing.
Android APK hosting and public iOS distribution remain pending; the buttons stay
hidden until verified real assets are configured.

When actual approved assets arrive, edit only `release-config.js`: the Android URL
must be a specific .apk asset under this repository's GitHub Release, with its
actual APK version and full sourceCommit SHA. The iPhone demo must be a real approved HTTPS recording link.
No download/video link appears until its data is provided. Recheck the asset and
update the current-placeholder tests before publishing that later change.

## Package the finished site

```sh
python package_site.py --output /tmp/onya-presentation.zip
```

The ZIP places index.html at its root and includes only allowlisted public static
files. It excludes mobile code, .git, tests, preview scripts and presentation drafts.
Extract it on the presentation laptop and open index.html, or serve that directory
locally with `python -m http.server 4173 --bind 127.0.0.1`.

## Reproduce browser checks

From the repository worktree root:

```sh
python website/onya/tests/browser_check.py --browser "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --output /tmp/onya-preview-checks
```

Python standard library only; requires an installed Chromium browser. Runs an
ephemeral localhost server and headless browser with a temporary profile. No
website source/data is uploaded. It writes screenshots/results outside Git.
Its cover screenshot can be copied to assets/devpost-cover.png after inspection.

## Git and evidence boundary

Final integration branch: `integration/final-hackathon`, checkpoint `6b0f865`.
Android and iOS use separate app targets and protocol packages. Android has
application-layer encryption; the preserved iOS baseline has plaintext envelopes.
Only same-platform phone pairs are supported. Current results and remaining device
steps are in [the integration record](../../docs/testing/final-integration.md).

Historical evidence copies remain byte-for-byte pinned to Security commit
`3f9eaf5574bae806fd20265fa40a0ce4e3b0b252`. Those reports are explicitly labelled
historical and do not describe the current Android encryption implementation.

Simulation state: available → discovered → requested → accepted → chat, or
requested → rejected. Out-of-order actions are ignored. Reset clears mock history.
This browser model is not a security test of the mobile implementation.
