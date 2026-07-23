# App Intent Confirmation

Source: [AppIntent.requestConfirmation()](https://developer.apple.com/documentation/appintents/appintent/requestconfirmation%28%29)

Last verified: 2026-07-10

## Apple Contract

Apple provides `requestConfirmation()` specifically for work that may be
destructive or unsafe. The intent pauses before the operation, continues only
when the person confirms, and throws if they cancel.

Newer overloads can supply localized action text, dialog, conditions, and an
interactive snippet. This is separate from `authenticationPolicy`:
authentication establishes that an authorized person/device is present, while
confirmation protects against ambiguity, accidental invocation, Siri
misrecognition, or a shortcut whose destructive consequence was not obvious.

## Lorvex Mapping

No Lorvex App Intent calls any `requestConfirmation` overload. Direct custom
intents immediately execute operations named:

- delete calendar event;
- delete habit and habit reminder policy;
- delete list;
- delete AI memory;
- delete preference;
- cancel task;
- remove checklist item/reminder/recurrence data;
- reset habit and clear/remove focus data.

Some of these operations emit sync tombstones, so an accidental invocation can
propagate to every device. A successful dialog shown after deletion is not a
confirmation and does not make the operation reversible.

## Required Design

Create an explicit destructive-intent classification and request confirmation
before the first database mutation. Pair it with the authentication policy in
[APP_INTENT_AUTHENTICATION.md](APP_INTENT_AUTHENTICATION.md); neither control
substitutes for the other.

Automations that are intentionally unattended require a deliberate product
decision. If confirmation is conditionally suppressed, define the safe context
with Apple's confirmation conditions and test Siri, Shortcuts, automations,
widgets, locked devices, and companion-device invocation separately.

