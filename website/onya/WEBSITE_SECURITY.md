# Website security and deployment boundaries

Scope: the static Onya presentation on `feat/onya-presentation`, including the
Android/iOS selector at `44026ff`. This review does not verify mobile security.

The visitor can click navigation, choose a platform and operate a fictional chat
simulation. No text-entry fields, forms, accounts, backend, API calls, analytics
or browser-storage writes are implemented. There is no database. App storage
claims remain separate from this website's behavior.

Both public HTML pages restrict content with meta Content Security Policy:
local styles/images/fonts; no connections, objects, forms or base URL changes.
The presentation permits local scripts; the evidence appendix permits no scripts.
There are no inline handlers or remotely loaded fonts/scripts. Chromium checks
observed no external resource requests or JavaScript runtime exceptions.

Mock chat content and configured release metadata use `textContent`. Existing
`innerHTML` assignments use fixed local templates, not visitor-supplied values.
The APK link stays hidden unless its URL is HTTPS, belongs to this repository's
GitHub Release APK path, and has a version and full source SHA. Userinfo and custom
ports are rejected. A recording URL is also HTTPS-only. Neither real asset was
supplied; neither download was verified or advertised as available.

Deployment checks an allowlisted ZIP, not the repository root. Current output
contains 19 public static files, with no mobile source, tooling, Git metadata,
APKs, IPAs or signing keystores. The workflow runs only on the website branch,
does not persist checkout credentials, and grants Pages/OIDC write permissions
only to the deployment job. Branch-limited environment policy requires owner setup.

Limits: CSP is defense in depth, not protection from a compromised repository or
approved deployment. Meta CSP cannot enforce `frame-ancestors`; custom response
headers have not been configured or claimed. Published HTTPS behavior, headers
and logged-out links remain unchecked because Pages is not enabled. Keep signing
keys out of this public repository. Real APK assets require a separate release
review and anonymous download check before enabling their link.

Actual checks: six local static groups and 27 Chrome browser checks passed;
GitHub Actions static checks and packaging passed. Deployment stopped at Pages
setup, HTTP 404. See DEPLOYMENT.md and VERIFICATION.md for evidence and limits.
