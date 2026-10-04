# Final integration deployment and app distribution

Source: `integration/final-hackathon`. The website remains static, with no backend.
This verification prepared deployment; it did not publish or change GitHub settings.

## Current status

Read-only checks on 2026-10-04 found Pages configured with `build_type=workflow`,
but `https://laxmi-srinivas.github.io/Offline-relay/` returned HTTP 404. No GitHub
Release assets are available. No TestFlight/App Store URL is configured.
The earlier [workflow attempt](https://github.com/Laxmi-Srinivas/Offline-relay/actions/runs/37209493790)
on `feat/onya-presentation` passed packaging but failed Pages configuration.
That historical failure is not a current successful deployment.

## Publish the website when approved

1. Review the local page, final scope and download notices.
2. An owner checks Settings → Pages → Source: GitHub Actions, and the
   `github-pages` environment permits `integration/final-hackathon`. If another
   site is present, confirm replacement before proceeding.
3. Push reviewed website/workflow changes to `integration/final-hackathon`.
   **This push triggers publication**, once repository settings permit it.
   No main checkout, merge or push is required. The workflow also declares manual
   dispatch; its availability depends on GitHub's default-branch workflow rules.
4. Inspect the actual workflow result and `deploy-pages` URL. Do not advertise
   the expected URL as live until it returns the reviewed site.
5. While signed out, check assets, platform selector, accept/reject/reset, mobile
   layout, `/Offline-relay/` subpath and any configured download links.

The workflow runs static checks and packages only public files from `website/onya`.
It uploads extracted ZIP contents, never the repository root. Checkout credentials
are not persisted. Only the deploy job gets Pages write/OIDC permissions. No mobile
build or signing credentials enter this workflow. Repository settings and actual
hosted HTTPS behavior are still manual verification steps.

Reference: [GitHub custom Pages workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).

## Android installation and APK hosting

Use an Android SDK/JDK host; this Mac currently has no Android SDK. From
`apps/offline_relay`, run `flutter pub get`, `flutter analyze`, `flutter test`,
then `flutter build apk --debug`. The artifact is
`build/app/outputs/flutter-apk/app-debug.apk`. Do not commit it. Record
`git rev-parse HEAD` and the artifact's SHA-256. Install that same artifact on both
Android demo devices, for example `adb -s SERIAL install -r PATH_TO_APK`.

For public download, upload the verified APK as a GitHub Release asset when
publication is approved. Copy its actual URL into `release-config.js`, together
with the APK version and full source commit. Check anonymous download and hash
before enabling the button. Update the placeholder assertions in the static test
when configuring real releases. No URL is fabricated here. The existing release
build configuration also uses debug signing; neither build is production signing.

## iPhone installation and distribution

The separate app compiles for simulator and unsigned device release. For the demo,
open `apps/offline_relay_ios/ios/Runner.xcworkspace` on a Mac, choose a local signing
team, and sign/install on each iPhone. Trust/Developer Mode may be required. Keep
team identifiers, certificates and provisioning files out of commits.

Public distribution requires the project's Apple Developer/App Store Connect
setup, a signed archive/upload and an actual TestFlight or App Store release.
External TestFlight testing may require Apple's beta review. Configure only the
real published Apple URL in `release-config.js` and verify it before advertising.
An unsigned Runner.app or arbitrary IPA URL does not install an iPhone app.
See [Apple's TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

## Offline fallback

From the repository root:

```sh
python3 website/onya/tests/static_check.py
python3 website/onya/package_site.py --output /tmp/onya-site.zip
python3 website/onya/preview.py
```

Extract the ZIP for a local presentation fallback. GitHub links still need Internet;
local fonts, illustration, simulation and historical reports work offline. Meta CSP
restricts local resources; custom HTTP security headers are not claimed configured.
