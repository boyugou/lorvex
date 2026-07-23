# App Intent Authentication Policy

Source: [AppIntent.authenticationPolicy](https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy)

Last verified: 2026-07-10

## Apple Contract

The default `AppIntent.authenticationPolicy` is `.alwaysAllowed`. Apple states
that this permits an intent to run without authentication even when the device
is locked.

The alternatives are:

- `.requiresAuthentication`: at least one participating device must be
  authenticated; an unlocked Apple Watch can authorize execution on a locked
  iPhone.
- `.requiresLocalDeviceAuthentication`: the device executing the intent must
  itself be unlocked. Apple specifically points to intents that access
  protected on-disk data as a use case.

Separately, `AppIntent.isDiscoverable` defaults to `true`, making an intent
available to Siri, Spotlight, Shortcuts, Apple Intelligence, and other system
experiences unless the app opts out.

Related sources:

- [IntentAuthenticationPolicy.requiresAuthentication](https://developer.apple.com/documentation/appintents/intentauthenticationpolicy/requiresauthentication)
- [IntentAuthenticationPolicy.requiresLocalDeviceAuthentication](https://developer.apple.com/documentation/appintents/intentauthenticationpolicy/requireslocaldeviceauthentication)
- [AppIntent.isDiscoverable](https://developer.apple.com/documentation/appintents/appintent/isdiscoverable)

## Lorvex Mapping

The current package links `LorvexSystemIntents` into macOS, iPhone/iPad, and
visionOS executables. Its own shortcut-provider comment explicitly says every
intent remains invokable from Shortcuts or an automation, not just the ten
curated App Shortcuts.

The source currently defines 93 `AppIntent` types in
`LorvexSystemIntents` and six in `LorvexWidgetIntents`. None declares
`authenticationPolicy`; none opts out through `isDiscoverable`; and no
intent-level confirmation calls were found.

The exposed operations include:

- reading memory contents, daily reviews, task/calendar content, preferences,
  diagnostics, and AI changelog data;
- exporting the database and calendar data as files;
- deleting memories, lists, habits, calendar events, preferences, reminders,
  and checklist items;
- batch create/complete/defer/move/reopen and arbitrary update operations.

The runners open the real shared SQLite store through
`LorvexCoreRuntimeFactory.makeForAppIntent()`. This is therefore a shipping
authorization boundary, not merely unused declarations or test scaffolding.

## Required Design

Classify every intent rather than inheriting the framework default:

1. Require local-device authentication for exports and access to sensitive
   on-disk content where execution on a remotely authenticated companion would
   still be inappropriate.
2. Require authentication for destructive or broad write operations unless a
   specific locked-device workflow has been deliberately approved.
3. Keep only narrow, consciously selected actions always allowed (for example,
   perhaps opening the app or capture-only/widget interactions), and test their
   abuse and privacy consequences.
4. Consider `isDiscoverable = false` for widget-only implementation intents
   that are not meant to appear as general Shortcuts/Siri capabilities.
5. Probe entity queries while locked. An intent policy must not be assumed to
   prove that pre-execution parameter suggestions cannot disclose task/list/
   habit/event names.

This policy should be represented as a central classification/gate so a future
intent cannot silently inherit `.alwaysAllowed` merely because its author
omitted the property.

Authentication does not replace confirmation for destructive operations. See
[APP_INTENT_CONFIRMATION.md](APP_INTENT_CONFIRMATION.md).
