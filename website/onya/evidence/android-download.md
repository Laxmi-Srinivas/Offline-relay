# Downloadable Onya Android security test APK

## Identity and provenance

- Display name: Onya in the launcher and user-visible app text.
- Version: 0.0.1 (version code 1).
- Package: `dev.offlinerelay.offline_relay.securitytest` (separate test install).
- Minimum Android API: 31; target API: 36.
- Security app source: `8bf78e29b9ff740c3336067dd610b4c4e25e9fca`; matching recorded source/report checkpoint: `54d30a0220fbe3b18b2a78a792cc9c6f482634a7`. The Android/shared app source in the build copy matched this recorded Security tree.
- Branding: only visible product strings were changed to Onya, following the naming in main commit `cf59a028907f5e73880db5c014c907b378fd3eea`. Security control logic from main was not imported. A temporary Gradle init script set the Android label and `.securitytest` application ID suffix. No mobile branch or tracked mobile file was changed.
- Build: `:app:assembleDebug` succeeded in a disposable copy. APK metadata reports version 0.0.1/code 1, min API 31 and target API 36.
- Signing: debug key; `apksigner verify --verbose` passed with APK Signature Scheme v2. Not production-signed or production-ready.
- Size: 156,123,305 bytes (about 149 MiB).
- SHA-256: `CF1550C7FE8E8F204C91F96906294F2651BE154AEEC3B621D38DFB89B55D7B34`.

Gradle emitted deprecation warnings for the existing Android Gradle configuration and an Android SDK XML version warning from installed native tooling; the build completed successfully.

## Install

Download the APK on Android 12 or newer, open it, and if prompted allow the browser/file manager to install apps. Review Android's debug/unknown-source warning before proceeding. It installs beside the ordinary app because it uses the `.securitytest` package suffix. Both nearby participants need this same test build installed.

## Test limits

The committed report records 60 shared Flutter tests and analysis passing, plus controlled foreground phone journeys on an earlier debug APK built from the same Security app code. The exact Onya-labelled distributed APK was rebuilt with only visible brand strings and the package label/suffix changed; it has not itself been installed or device-tested. Background chat delivery failed with a GATT write error; rejection kept chat closed but surfaced a Bluetooth error. Bluetooth link encryption/authentication and active peer identity are not established. Do not use this debug build for sensitive conversations.
