# iOS security work

## Committed baseline and provenance

The user authorized hardening existing committed iOS functionality on the single
Security branch. Imported only changed files under `apps/offline_relay/ios` and
the existing Swift native test entry point from immutable upstream commit
`57d8348fd4f3a7b29742925aed7804370ff993fe` (including its existing background and
notification implementation). Shared Dart/Android hardening is retained; upstream
Dart, Android, UI and unrelated branch files are not imported. This is a selective
source import, not a merge, cherry-pick or claim that this combined app was already
validated by the contributor. Original commit authorship/history remains intact;
the new import commit records the actual security-work author/time and provenance.

Windows has no Swift compiler on PATH or Xcode. Native tests and iOS build/device
checks must be recorded as NOT RUN until performed with suitable tooling. Existing
contributor assertions and physical-device records are not this review's results.

## Applicable existing functionality

CoreBluetooth discovery/duplex framing, foreground peer chat, app-owned background
helper availability, local request notifications and availability restoration exist
in source. Background runtime guarantees require devices. Helper enabled/profile
values are persisted in UserDefaults; chat, request and connection state is in
memory. No website, database or Internet relay action is introduced.
