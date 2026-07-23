#if canImport(AppKit)
  import AppKit
#endif
@preconcurrency import EventKit
import Foundation
import LorvexCore
import LorvexDomain
import LorvexStore

extension LiveEventKitAccess {
  /// Stable provider event key: the cross-store external identifier when
  /// present (survives calendar moves), else the event identifier.
  static func stableKey(for event: EKEvent) -> String {
    if let external = event.calendarItemExternalIdentifier, !external.isEmpty {
      return external
    }
    return event.eventIdentifier ?? event.calendarItemIdentifier
  }

  static func fetchedEvent(from event: EKEvent) -> EventKitFetchedEvent {
    let eventTimeZone = event.timeZone ?? .current
    return EventKitFetchedEvent(
      key: stableKey(for: event),
      title: event.title?.isEmpty == false ? event.title : nil,
      notes: event.notes,
      startDate: AllDayEventSpan.dayKey(for: event.startDate, timeZone: eventTimeZone),
      startTime: event.isAllDay
        ? nil : clockTimeKey(for: event.startDate, timeZone: eventTimeZone),
      endDate: lorvexEndDate(from: event, timeZone: eventTimeZone),
      endTime: event.isAllDay
        ? nil : event.endDate.map { clockTimeKey(for: $0, timeZone: eventTimeZone) },
      allDay: event.isAllDay,
      location: event.location?.isEmpty == false ? event.location : nil,
      timezone: event.timeZone?.identifier,
      recurrence: EventKitRecurrenceBridge.json(from: event.recurrenceRules?.first),
      recurrenceExceptions: nil,
      color: hexColor(from: event.calendar?.cgColor),
      organizerEmail: participantEmail(event.organizer),
      url: event.url?.absoluteString,
      attendees: fetchedAttendees(from: event.attendees))
  }

  /// EventKit stores an all-day end as an exclusive boundary while Lorvex
  /// stores the final occupied day inclusively. Timed events already share
  /// instant semantics and pass through unchanged.
  private static func lorvexEndDate(from event: EKEvent, timeZone: TimeZone) -> String? {
    guard let endDate = event.endDate else { return nil }
    guard event.isAllDay else {
      return AllDayEventSpan.dayKey(for: endDate, timeZone: timeZone)
    }
    let startDate = event.startDate ?? endDate
    let inclusiveEnd = AllDayEventSpan.inclusiveEnd(
      start: startDate,
      exclusiveEnd: endDate,
      calendar: AllDayEventSpan.gregorianCalendar(timeZone: timeZone))
    return AllDayEventSpan.dayKey(for: inclusiveEnd, timeZone: timeZone)
  }

  /// Render an instant as the event's own 24-hour wall-clock time. The date
  /// and time fields must use the same timezone later stored in `source_tzid`;
  /// formatting them in the device timezone and merely labelling them with the
  /// event timezone changes the represented instant during timeline projection.
  private static func clockTimeKey(for date: Date, timeZone: TimeZone) -> String {
    let components = AllDayEventSpan.gregorianCalendar(timeZone: timeZone)
      .dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
  }

  /// Map `EKEvent.attendees` into the platform-neutral projection, dropping
  /// participants with no addressable email (the read path keys attendees by
  /// email, so a name-only participant renders nothing) and normalizing each
  /// `EKParticipantStatus` to the canonical RFC 5545 PARTSTAT subset.
  static func fetchedAttendees(from participants: [EKParticipant]?) -> [EventKitFetchedAttendee] {
    guard let participants else { return [] }
    return participants.compactMap { participant in
      guard let email = participantEmail(participant) else { return nil }
      return EventKitFetchedAttendee(
        email: email,
        name: participant.name?.isEmpty == false ? participant.name : nil,
        status: attendeeStatus(from: participant.participantStatus))
    }
  }

  /// A participant's email, stripped of the `mailto:` scheme EventKit wraps it
  /// in. `nil` when the participant carries no non-empty address.
  static func participantEmail(_ participant: EKParticipant?) -> String? {
    guard let participant else { return nil }
    let raw = participant.url.absoluteString
    let email = raw.lowercased().hasPrefix("mailto:")
      ? String(raw.dropFirst("mailto:".count)) : raw
    return email.isEmpty ? nil : email
  }

  /// Map `EKParticipantStatus` onto the canonical attendee-status vocabulary.
  /// Undecided (`pending`) and indeterminate (`unknown`, plus delegated /
  /// completed / in-process) states fold to `needs-action`, matching RFC 5545.
  static func attendeeStatus(from status: EKParticipantStatus) -> AttendeeStatus {
    switch status {
    case .accepted: return .accepted
    case .declined: return .declined
    case .tentative: return .tentative
    default: return .needsAction
    }
  }

  /// `#RRGGBB` for an EventKit calendar's color, resolved in sRGB, so ingested
  /// events carry their source calendar's color the same way list/habit colors
  /// are persisted. `nil` when the color can't be resolved to RGB.
  static func hexColor(from cgColor: CGColor?) -> String? {
    guard let cgColor else { return nil }
    #if canImport(AppKit)
      guard let srgb = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else { return nil }
      return String(
        format: "#%02X%02X%02X",
        Int((srgb.redComponent * 255).rounded()),
        Int((srgb.greenComponent * 255).rounded()),
        Int((srgb.blueComponent * 255).rounded()))
    #else
      return nil
    #endif
  }

  static func notesWithMarker(userNotes: String?, lorvexID: String) -> String {
    let marker = "\(lorvexCalendarEventPrefix)\(lorvexID)"
    if let base = userNotes, !base.isEmpty {
      return "\(base)\n\(marker)"
    }
    return marker
  }

  /// Recover the user-authored portion from a previously marked EventKit event
  /// before a preserve-only rewrite. The marker is always appended as its own
  /// line, so removing only an exact marker line cannot eat ordinary notes that
  /// merely mention a similar prefix.
  static func userNotes(fromMarkedNotes notes: String?, lorvexID: String) -> String? {
    guard let notes else { return nil }
    let marker = "\(lorvexCalendarEventPrefix)\(lorvexID)"
    let preserved = notes.components(separatedBy: .newlines)
      .filter { $0 != marker }
      .joined(separator: "\n")
    return preserved.isEmpty ? nil : preserved
  }

  /// YMD form of an EventKit instant in its event timezone, so a recurring
  /// occurrence's original day and its fetched wall-clock fields compare in
  /// the same civil calendar. Scan-window callers may omit the timezone to use
  /// one snapshot of the current device timezone.
  static func ymdString(from date: Date, timeZone: TimeZone = .current) -> String {
    AllDayEventSpan.dayKey(for: date, timeZone: timeZone)
  }
}
