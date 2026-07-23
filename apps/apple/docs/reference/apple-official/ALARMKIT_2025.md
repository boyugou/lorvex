# AlarmKit, 2025

Primary sources:

- [Wake up to the AlarmKit API — WWDC25](https://developer.apple.com/videos/play/wwdc2025/230/)
- [NSAlarmKitUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsalarmkitusagedescription)

Last verified: 2026-07-10

## Apple Contract

AlarmKit on iOS and iPadOS 26 provides timers and alarms that can appear on the
Lock Screen, Dynamic Island, StandBy, and Apple Watch. People opt in per app.
The app must provide a meaningful `NSAlarmKitUsageDescription`; a missing or
empty value prevents alarm scheduling.

An AlarmKit alarm is intentionally more interruptive than an ordinary local
notification. It is not a general-purpose replacement for reminder delivery.

## Lorvex Mapping

Lorvex's normal task reminders should remain notifications. Promoting every due
task to an alarm would be disproportionate, create permission fatigue, and
change the product's interruption semantics.

A narrow future fit is a user-started focus timer or a deliberately selected
must-alert event. It should be opt-in at the individual workflow level, clearly
distinguished from task reminders, and paired with cancellation/rescheduling
tests.

AlarmKit can be availability-gated while retaining the proposed iOS 18 minimum.
It does not require a persistent-schema change unless Lorvex introduces a new
user-visible alarm concept; avoid pre-reserving such fields before the product
behavior exists.
