# App Intent Authentication Policy

Source: [AppIntent.authenticationPolicy](https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy)

Last verified: 2026-07-10 (Apple contract), 2026-11-22 (Lorvex mapping)

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

Checked against the built app on 2026-11-22.

Every App Intent type declares its `authenticationPolicy` in its own body as a
`static let` with a literal value: 89 types across `LorvexSystemIntents`,
`LorvexWidgetIntents`, `LorvexWidgetExtension`, and the Focus filter. The
declaration has to be in the type because the build's App Intents metadata
step reads only what a type declares itself; a value from a protocol extension
never reaches `Metadata.appintents`, which then records the intent as
`.alwaysAllowed`.

The system intents name one of three tiers
(`Sources/LorvexSystemIntents/LorvexIntentSecurity.swift`):

- `.alwaysAllowed`: opening the app and adding a task, by the capture action
  or by Siri's create action.
- `.requiresAuthentication`: every change to stored data and the reads that
  return only names and counts.
- `.requiresLocalDeviceAuthentication`: reads that return task, calendar,
  memory, or review content, and the data exports.

The two widget-tap intents are `.alwaysAllowed`, since a tap on a Lock Screen
widget must still act, and declare `isDiscoverable = false`.

Three checks hold this in place. `script/verify_system_entrypoints.py` fails
when an intent type lacks the declaration, names more than one tier, or
declares a policy other than its tier's. `script/extract_app_intents_metadata.py`,
which writes the Mac app's metadata, fails when an action reaches the metadata
without a declared policy. `IntentSecurityClassificationTests` asserts the
run-time values for a sample of intents in each tier.

Not measured:

- Whether the system decides lock-screen access from the built metadata or
  from the running app. The metadata and the running value now agree, so the
  answer no longer changes what a locked device allows.
- Whether an entity query (the task, list, habit, or event names Siri and
  Shortcuts offer for a parameter) runs while the device is locked. An
  intent's policy governs running the intent and says nothing about the
  suggestions shown before it runs.

Authentication does not replace confirmation for destructive operations. See
[APP_INTENT_CONFIRMATION.md](APP_INTENT_CONFIRMATION.md).
