# Website verification and handoff

## Source and publication boundary

Website branch: `feat/onya-presentation`, isolated TEMP worktree. Base:
`67acd0632eb1965482d7b745e06f1ef0c83b55f5`. First website commit: `c2cab45`.
Only `website/onya/` and its dedicated `.github/workflows/onya-pages.yml` are changed.
Mobile checkouts are untouched; no Security/UI merge or history rewrite.
Website publication and branch push: NOT PERFORMED, awaiting final preview approval.

## Actual website checks

- Python standard-library static checks: PASS (six groups): local links/anchors,
  accessible references, fonts, evidence hashes, unavailable release actions,
  allowlisted deployment ZIP and primary text/control/status contrast (4.5:1).
- Chrome 154.0.8037.97: all 26 browser checks passed on the completed page.
- Edge 154.0.4258.53: all 26 browser checks passed; final explanatory copy/source
  metadata was subsequently clarified and checked again in Chrome.
- Screens checked at 1440, 1024, 768, 390 and 320 CSS pixels. Every active simulation
  stage fits inside each phone, no page horizontal overflow.
- Discover/request/accept/chat, reject, stale/out-of-order actions and reset passed.
  Keyboard Enter/Tab, focus movement/outline and reduced motion passed.
- Local images/scripts/fonts/reports, anchors and evidence appendix loaded.
  `/Offline-relay/` project-path preview loaded both fonts/assets and full interaction.
- JavaScript-disabled story and direct file:// fallback passed with HTTP/HTTPS
  blocked. File preview may use a system font; localhost gives consistent typography.
- No site JavaScript exceptions or external resource requests in the final run.
- Original desktop/mobile hero and simulation screenshots visually inspected.
  Generated Devpost cover is a labelled project illustration, not app evidence.

Exact commands, run from website worktree root:

```powershell
python website/onya/tests/static_check.py
python website/onya/tests/browser_check.py --browser "C:/Program Files/Google/Chrome/Application/chrome.exe" --output C:/Users/mamid/AppData/Local/Temp/Onya-preview-checks
python website/onya/tests/browser_check.py --browser "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" --output C:/Users/mamid/AppData/Local/Temp/Onya-edge-checks
python website/onya/package_site.py --output C:/Users/mamid/AppData/Local/Temp/Onya-presentation.zip
```

Native installed browsers, temporary test profiles and ephemeral localhost servers;
no dependency installation, external scanner or source upload. Test artifacts live
outside Git. GitHub Actions execution is prepared but NOT RUN. The local package
contains 19 public static files; no mobile/source-repo metadata, tools, signing data
or APK. All first-party paths are relative for the actual GitHub Pages project path.

## Issues found and corrected

- Test harness initially assumed one WebSocket handshake reason phrase; accepted
  the correct 101 response after validating the handshake key.
- A test-expression typo was corrected; it was not a page runtime error.
- A real 320px phone-panel/navigation overlap was found and fixed by allowing
  narrow-screen phones to grow with content. All stages now fit.
- Copied font licenses had inherited trailing whitespace; only website copies
  were tidied. Website-local LF attributes preserve report byte hashes on checkout.
  Original mobile fonts/licenses were not modified.
- User selected GitHub Pages; the Cloudflare draft/headers were removed before
  final deployment preparation. No Cloudflare connection or upload occurred.

## App evidence is separate

- Android feature/control descriptions refer to Security APK source
  `8f2621c75fe31239d15062be2b663e8ee64fdca1`, not a demonstrated/published beta.
  `git diff 8f2621c 3f9eaf5 -- apps/offline_relay/lib apps/offline_relay/android
  packages/relay_transport apps/offline_relay/pubspec.yaml apps/offline_relay/pubspec.lock`
  was empty: these production paths did not change before the later report snapshot.
- The 38-test record is at `056693dbd08e192131b67e97b8bf489a5b65a346`; included
  report snapshot is `3f9eaf5574bae806fd20265fa40a0ce4e3b0b252`. Mobile tests were
  not rerun for this website. Older APK results do not verify upstream UI 67acd06.
- iPhone app build/physical tests are team-reported, corroborated by the contributor
  record at iOS source snapshot `57d8348fd4f3a7b29742925aed7804370ff993fe`.
  Exact tested device-build SHA and a recording were not supplied. Personal Team
  signing is attributed to the team. Prepared native Security fixes remain separate
  and pending. No Android–iPhone compatibility result is claimed.
- Both nearby users need the mobile app installed beforehand. Availability is
  not guaranteed indefinitely. No “nothing is stored” claim is made.

## Remaining checks before final submission

1. User approves this preview and website publication.
2. Configure repository Pages/environment, push only the website branch and run
   the prepared workflow. Inspect the actual returned URL while logged out.
3. Repeat links/assets/interaction checks on the published HTTPS site.
4. Receive and verify a real published APK URL, actual version and source SHA;
   verify download while logged out before enabling the beta link. No asset yet.
5. Receive an actual recording before enabling “Watch iPhone demo.” No public
   iOS download, App Store, TestFlight or IPA link.
6. Safari/Firefox, physical browser devices, full screen-reader operation and
   deployed HTTP headers are not verified by these local Chromium checks.
7. Team reviews Devpost draft and event-specific rules; no submission has occurred.

Local fallback: extracted static ZIP or Python localhost preview. Speaking script,
pre-demo checklist and Devpost draft are in presentation/. Deployment instructions
are in DEPLOYMENT.md. No guarantee of error-free operation or competition outcome.
