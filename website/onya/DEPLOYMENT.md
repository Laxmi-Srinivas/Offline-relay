# GitHub Pages deployment — authorized, awaiting owner setup

The user selected GitHub Pages with a free github.io URL and subsequently requested
deployment. The verified website was pushed on `feat/onya-presentation` at
`44026ff94b3f291ecf4ca1144c17c2966765e8f9`. It is not live: Pages is not enabled.
Workflow: `.github/workflows/onya-pages.yml`; source branch:
`feat/onya-presentation`. No domain purchase, mobile-branch change, merge or rewrite.

## Prepared deployment

The workflow triggers only on website/deployment changes pushed to the website
branch. It checks static assets/evidence, packages an allowlisted ZIP, extracts it
under the runner's TEMP directory and uploads only that output. It never publishes
the repository root or mobile source. Build has read permissions; only deploy has
Pages write/OIDC permissions. Checkout does not persist credentials. No backend,
cloud secrets, database or npm installation steps.

## Actual first deployment attempt

[Run 37209493790](https://github.com/Laxmi-Srinivas/Offline-relay/actions/runs/37209493790)
passed checkout, static checks and packaging on GitHub's runner. Configure Pages
failed with HTTP 404: the repository has no Pages site. Upload and deploy were
skipped. Anonymous requests to the expected project URL returned HTTP 404.
The authenticated account has push access but not admin/maintain access. No
repository settings were changed. The user will ask the owner to enable Pages.

Owner action: Settings → Pages → Build and deployment → Source → GitHub Actions.
If needed, Settings → Environments → github-pages must permit
`feat/onya-presentation`. Rerun the failed workflow after setup; do not edit main.
The local preview and ZIP remain available while deployment is blocked.

## Publication sequence

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
execution has been checked through packaging; successful deployment and final
environment settings remain unverified. The first trigger
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
