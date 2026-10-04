# Delivery plan while device testing is deferred

Device testing is postponed at the user's request. Local checks stay alongside
each change; deferred checks are not reported as passed. Existing branches remain
read-only and changes stay on Security. Pending Swift fixes remain uncommitted
until the verification boundary documented in IOS.md is satisfied.

## Work we can finish now

1. Prepare presentation content grounded in implemented BLE peer chat: discovery,
   explicit approval, text exchange, helper availability and notifications.
2. Explain the trust boundaries and demonstrated security properties with actual
   evidence. Link each claim to the relevant source, regression and result.
3. Prepare a short demo script, synthetic test data and a recorded-demo fallback.
   Record a device demonstration only after it has actually been performed.
4. Prepare release records: source SHA, artifact hash, build instructions, known
   limitations and verification status. The existing debug APK is a test artifact.
5. Compare future contributor commits before incorporating overlapping fixes or
   the newer UI; do not automatically merge or rewrite either branch's history.

Presentation content can later be used in the separately planned presentation
website. That website is not currently implemented and is not the app/backend.
Hosting provider, distribution method and website implementation remain undecided.

## Presentation outline

- Problem and scope: nearby peer communication when Internet access is unavailable.
- Existing flow: helper offers availability; another phone discovers it, requests
  a connection, waits for approval, then exchanges text over BLE.
- Architecture: Flutter UI/controller, native BLE adapter and a nearby peer;
  Android helper foreground service and committed iOS app-owned helper code.
- Security demonstration: consent checks, stale-session isolation, bounded memory,
  duplicate suppression, cleanup and operation deadlines. Show test evidence.
- Evidence: 38 shared Flutter tests and analysis passed. Android policy tests and
  the earlier debug APK build passed as recorded; Swift/iOS fixes await verification.
- Honest limits: self-asserted names, unverified radio confidentiality/authentication,
  no implemented Internet relay/backend/database, and deferred device checks.

Do not advertise end-to-end encryption unless the source and verification establish
it. Do not describe tests using simulated events as successful physical BLE tests.
The newer upstream UI is not covered by the older Security APK build.

## Deferred verification and release gate

Before presenting a live radio demo or distributing a release as validated:

- Mac: compile/run native Swift policy tests and build the iOS app, then commit
  verified native fixes. Record failures and actual outcomes.
- Controlled phones: normal approval/chat, rejection, background notifications,
  reconnect/session isolation, malformed input, resource limits and cleanup.
- Verify actual Bluetooth encryption/authentication and inspect synthetic data in
  logs, preferences, files and backups.
- Rerun applicable checks after final contributor/UI integration.
- Android release signing needs a deliberate configuration: current
  `android/app/build.gradle.kts` release block still uses the debug signing config.
  Do not generate/store signing secrets in Git or label the debug build production.

Publishing a presentation website and distributing an app are separate decisions.
No website deployment, store submission, signing-key generation or device install
is performed by this plan.
