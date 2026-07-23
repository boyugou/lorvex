# App Intent Execution Modes

Source: [AppIntent.supportedModes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes)

Last verified: 2026-07-10

## Apple Contract

`supportedModes` is the current App Intents API for declaring whether an
action runs in the background, requires the foreground immediately, or may
transition to the foreground dynamically/deferred. The intent can inspect its
actual current mode through `systemContext`.

Apple has deprecated `openAppWhenRun` and directs new code to
`supportedModes`. It also warns that setting the legacy property to `true` is
an error for an intent that runs in an app extension.

Related source: [AppIntent.openAppWhenRun](https://developer.apple.com/documentation/appintents/appintent/openappwhenrun)

## Lorvex Mapping

All 99 App Intent types across `LorvexSystemIntents` and
`LorvexWidgetIntents` declare `openAppWhenRun`; none declares
`supportedModes`. Ninety-six use `false`, while the three explicit open intents
use `true`.

This is not a current data-loss bug. It is a broad deprecated-API dependency
across a large system-integration surface, and the Boolean cannot express the
more precise execution needs of export, authentication, confirmation,
foreground navigation, and widget actions.

## Maintenance Direction

Migrate as part of the same centralized intent classification required by
[APP_INTENT_AUTHENTICATION.md](APP_INTENT_AUTHENTICATION.md): every intent
should declare execution mode, authentication, discoverability, and
confirmation semantics in one auditable policy. Preserve deployment-floor
compatibility with an availability/back-deployment design and verify with the
current required Xcode toolchain.

