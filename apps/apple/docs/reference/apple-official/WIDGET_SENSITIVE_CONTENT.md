# Hiding Sensitive Widget Content

Source: [Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)

Last verified: 2026-07-10

## Apple Contract

Widgets and watch complications can remain visible on the Lock Screen and on
Always-On displays. Apple tells developers to review content for sensitivity
and use `privacySensitive(_:)` so a person's system privacy setting can replace
that content with a placeholder or redaction.

An extension-wide Data Protection entitlement is an alternative when all
widget content should disappear at a chosen lock state. Control widgets also
support privacy-sensitive marking; marking the control template protects its
content and state on the Lock Screen.

## Lorvex Mapping

Confirmed correct:

- the iOS accessory-inline title is privacy-sensitive;
- task titles in the accessory-rectangular widget are privacy-sensitive;
- Watch rectangular and corner complication task titles are
  privacy-sensitive.

Remaining gaps:

- `SmallSystemWidgetView`, `SystemWidgetView`, and `TodayTaskRowView` display
  task titles without a privacy-sensitive marker;
- the medium/large Focus widget can also display a user-authored briefing
  without the marker;
- `LorvexFocusControlWidget` puts the first focus-task title in a control label
  but marks neither the label nor the control template privacy-sensitive;
- the widget/complication entitlement files do not use extension-wide Data
  Protection as a fallback.

Standard widgets can appear in locked/always-visible contexts such as StandBy,
iPad/iPhone Lock Screen, Mac desktop from iPhone, and CarPlay. The control can
appear on the Lock Screen. Therefore covering only the accessory families is
not a complete sensitive-content policy.

## Required Verification

Test every supported family and the control with Lock Screen widget data
disabled and with Apple Watch “Hide Sensitive Complications” enabled. The
expected result should keep non-sensitive counts/status visible while redacting
task titles, briefing text, and any other user-authored content.

