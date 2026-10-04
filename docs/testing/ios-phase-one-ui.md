# Phase 1 UI parity on ios-mvp

Inspected UI commit `67acd0632eb1965482d7b745e06f1ef0c83b55f5` by fetching its
object and comparing files; no branch merge/rebase or main modification.
Checkpoint based on `57d8348fd4f3a7b29742925aed7804370ff993fe`, preserving
the existing multiple-outgoing-request implementation.

Copied main's theme, bottom navigation, Inter/Manrope font binaries and OFL licenses,
font declarations, and baseline widget tests. Adapted main.dart, Home, Nearby,
Profile, and person cards. Profile uses the neutral Nearby profile label instead
of Android phone. Person cards use Connect / Requesting… / Connected to preserve
the iOS multi-request interaction. Home header and status labels can flex on narrow
screens. Snackbar access uses a key below MaterialApp instead of a parent context.

The iOS controller was not replaced. Added only UI error/search completion helpers
and a 12-second presentation timer. Starting a request cancels that timer, without
cancelling discovery or other requests. An empty timed search can finish cleanly;
previously discovered peers remain connectable through native peripheral retrieval.
Main's pending-only Nearby layout was replaced by independently visible helper
cards. Find Nearby from Home returns to existing pending requests without restarting
discovery. Choosing helper availability while outgoing requests exist explicitly
cleans up those requests before switching roles.

The pending map, connection/request correlation, synchronous first-winner claim,
loser cleanup, stale-event filters, selected-only chat, and isolated rejection/
disconnect handling are retained. Transport/native/helper/notification/UUID/framing/
ACK/profile code is byte-identical to the working tree before this UI pass.
Android native and experiments/ble_poc remain unchanged.

Validation: Flutter analysis passed; all 37 app tests passed, including existing
multi-request/controller/transport tests, updated baseline UI tests, and six new
widget scenarios. Native Swift and transport contract tests passed. Simulator debug
build and git diff --check passed. This validated checkpoint is committed only on
`ios-mvp`; no merge, rebase, or PR.

## Physical validation confirmation

The tester confirmed that physical iPhone validation of the current build is
finished. Release builds containing the Phase 1 UI and concurrent request code
were installed and launched on Jubilee high school 5G (iOS 26.6.2) and iPhone
(iOS 26.2.1). Validation is on real iPhones, not the simulator.

This confirmation records the current build as physically validated. The tester
did not supply an itemized three-phone result, so the matrix below remains a
repeatable regression checklist rather than evidence that each scenario passed.
Earlier detailed helper-background and request-notification validation records
remain distinct. Process restoration and force-quit limitations are unchanged.

## Physical regression checklist

Use three iPhones: Offline User A and Internet Helpers B/C. Navigate Home/Profile/
Nearby, set names, enable both helpers, discover both, and send requests to both.
Confirm both show requests/notifications and per-card Requesting state remains
independent. Accept C first (and repeat with B); verify the loser closes, cannot
steal chat or inject messages, and winner bidirectional chat works. Test one pending
Reject/disconnect preserving the other, then return/reconnect. Repeat helper
background/lock-screen notification and notification-tap request replay with the new
shell. Record itemized device results when repeating this checklist.
