# EventKit Calendar Sources

Source: [EKSource](https://developer.apple.com/documentation/eventkit/eksource)

Last verified: 2026-07-10

## Apple Contract

An `EKSource` represents the account to which an EventKit calendar belongs.
Apple's source types include local, Exchange, and CalDAV; the CalDAV case also
represents iCloud. An `EKCalendar` belongs to one of these sources.

Related sources:

- [EKSourceType.calDAV](https://developer.apple.com/documentation/eventkit/eksourcetype/caldav)
- [EKSourceType.exchange](https://developer.apple.com/documentation/eventkit/eksourcetype/exchange)
- [EKCalendarType](https://developer.apple.com/documentation/eventkit/ekcalendartype)

## Lorvex Mapping

The macOS EventKit adapter creates a dedicated Lorvex calendar when needed.
`preferredCalendarSource` explicitly chooses a CalDAV source first, with an
inline rationale that this lets the Lorvex calendar sync across the user's
devices. It falls back to a local source, the default calendar's source, or any
available source.

Event write-back places the user-provided title, start/end time, all-day flag,
location, notes plus a Lorvex identifier marker, and recurrence rules in that
calendar. A user may also select another writable calendar, which can belong to
an iCloud, Google/CalDAV, Exchange, or other configured account.

Relevant code:

- `EventKitEventStoring.swift:51-57`
- `LiveEventKitAccess.swift:210-243`
- `LiveEventKitAccess.swift:294-307`

## Privacy Mismatch

`PRIVACY.md` currently says EventKit access is local to the device and that
Lorvex does not transmit calendar data except through its CloudKit and MCP
paths. That is not a complete description of write-back to a provider-backed
system calendar. Lorvex may not operate or directly contact the provider's
server, but saving to the account calendar is intended to let the operating
system/provider sync those fields off device.

This does not by itself imply developer collection for the App Store privacy
label. It does require accurate user-facing disclosure that calendar write-back
is governed by the selected Calendar account/provider and may sync through that
provider.

