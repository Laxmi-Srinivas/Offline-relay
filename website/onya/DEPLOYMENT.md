# GitHub Pages deployment — final approval required

The user selected GitHub Pages with a free github.io URL. Nothing has been pushed
or published on the website branch. Preview approval is the remaining publication
gate. Workflow: `.github/workflows/onya-pages.yml`; source branch:
`feat/onya-presentation`. No domain purchase, mobile-branch change, merge or rewrite.

## Prepared deployment

The workflow triggers only on website/deployment changes pushed to the website
branch. It checks static assets/evidence, packages an allowlisted ZIP, extracts it
under the runner's TEMP directory and uploads only that output. It never publishes
the repository root or mobile source. Build has read permissions; only deploy has
Pages write/OIDC permissions. Checkout does not persist credentials. No backend,
cloud secrets, database or npm installation steps.

## Publication sequence — ONLY after approval

1. Confirm the approved website commit and inspect the finished preview.
2. With repository-admin access, set Settings → Pages → Source to GitHub Actions.
   Check the `github-pages` environment permits only `feat/onya-presentation`.
   If a Pages site already exists, confirm replacement is intended before changing it.
3. Push only the website branch. That push triggers publication if settings permit
   it. Later website-branch pushes also redeploy; treat each as publication.
4. Inspect build/deploy logs and the actual URL returned by deploy-pages. Expected
   project URL: `https://laxmi-srinivas.github.io/Offline-relay/`; it is not claimed
   live or verified until deployment succeeds.
5. Check hosted assets, accept/reject/reset, mobile layout, evidence links, project
   subpath, download placeholders and actual HTTPS behavior.
6. Add the actual approved URL to Devpost after checking it. Keep the identical ZIP
   locally for offline fallback.

[GitHub's custom Pages workflow guide](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
describes the official configure/upload/deploy actions used here. GitHub workflow
execution and repository/environment settings remain unverified. The first trigger
uses push: manual workflow dispatch generally needs its definition on the default
branch, and this work must not modify main to enable that.

## App access

Android shows “Android download being prepared.” No download anchor appears until
the user supplies the actual published APK/version/source commit in release-config.js. It must
target this repository's specific GitHub Release .apk asset. Verify the asset and
update placeholder tests before publishing later changes. Beta is not production.

iOS shows “iOS public download not available yet.” Existing physical app testing
and free Personal Team signing are team-reported; prepared Security fixes have
separate pending checks. A “Watch iPhone demo” link appears only when a real approved
HTTPS recording is supplied. No App Store, TestFlight or IPA buttons.

## Website protection and limits

HTML has a restrictive meta CSP: local scripts/assets only, no API connections,
object embedding or forms. No user input/persistence; mock chat/version uses
textContent. Release links require HTTPS. GitHub Pages does not apply Cloudflare
_headers files; the earlier draft was removed. Frame-ancestor policy cannot be
enforced through meta CSP, and custom hosting headers are not claimed configured.
Inspect actual hosting behavior/headers after approved deployment.

## Rollback

Retain the previous approved ZIP/commit. Use the local copy if hosting fails.
Fix forward on the website branch and redeploy approved output. Do not rewrite
history or change mobile branches. Local success is not a guarantee of zero errors.
