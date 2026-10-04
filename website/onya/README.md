# Onya presentation

One responsive presentation page, a small evidence appendix and a deterministic
two-phone illustration. Plain HTML/CSS/JavaScript, self-hosted Manrope/Inter (OFL
licenses included) and original SVG artwork. No package manager, build installation, real
Bluetooth, backend, database, tracking, remote font or external API.

## Preview now

From this folder:

```powershell
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
- [Deployment proposal, awaiting approval](DEPLOYMENT.md)
- [Source hashes and commits](evidence/sources.json)
- [Devpost cover, 1200 × 800 PNG](assets/devpost-cover.png): project illustration,
  not an app screenshot. Editable source: `presentation/cover.html` / `cover.css`.

Deployment target: free GitHub Pages, with only allowlisted website output uploaded
by `.github/workflows/onya-pages.yml`. Initial push/publication awaits approval.
Android shows a preparation notice; no APK URL/version was supplied. iOS public
download is unavailable. Physical iPhone app testing is team-reported and separate
from our pending native Security verification.

When actual approved assets arrive, edit only `release-config.js`: the Android URL
must be a specific .apk asset under this repository's GitHub Release, with its
actual APK version and full sourceCommit SHA. The iPhone demo must be a real approved HTTPS recording link.
No download/video link appears until its data is provided. Recheck the asset and
update the current-placeholder tests before publishing that later change.

## Package the finished site

```powershell
python package_site.py --output C:/Users/mamid/AppData/Local/Temp/Onya-presentation.zip
```

The ZIP places index.html at its root and includes only allowlisted public static
files. It excludes mobile code, .git, tests, preview scripts and presentation drafts.
Extract it on the presentation laptop and open index.html, or serve that directory
locally with `python -m http.server 4173 --bind 127.0.0.1`.

## Reproduce browser checks

From the repository worktree root:

```powershell
python website/onya/tests/browser_check.py --browser "C:/Program Files/Google/Chrome/Application/chrome.exe" --output C:/Users/mamid/AppData/Local/Temp/Onya-preview-checks
```

Python standard library only; requires an installed Chromium browser. Runs an
ephemeral localhost server and headless browser with a temporary profile. No
website source/data is uploaded. It writes screenshots/results outside Git.
Its cover screenshot can be copied to assets/devpost-cover.png after inspection.

## Git and evidence boundary

Branch: `feat/onya-presentation`. Base: origin/main
`67acd0632eb1965482d7b745e06f1ef0c83b55f5`. Separate worktree; files confined to
`website/onya/`. No mobile files changed, no merge, no history rewrite. No publication
or website-branch push is authorized until the user approves the finished preview.

Evidence is copied byte-for-byte from Security commit
`3f9eaf5574bae806fd20265fa40a0ce4e3b0b252` with source paths and SHA-256 hashes.
The website verifies those records, not mobile runtime behavior. No invented test
dates. Shared Flutter results, prior Android APK results and pending iOS/device
checks are separate. Security and newer upstream UI are not assumed integrated.

Simulation state: available → discovered → requested → accepted → chat, or
requested → rejected. Out-of-order actions are ignored. Reset clears mock history.
This browser model is not a security test of the mobile implementation.
