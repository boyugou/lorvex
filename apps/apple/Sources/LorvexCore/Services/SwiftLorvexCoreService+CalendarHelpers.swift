import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexWorkflow

extension SwiftLorvexCoreService {
  static func patchString(_ value: String?) -> Patch<String> {
    guard let value else { return .unset }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? .clear : .set(trimmed)
  }

  static func calendarEventType(_ value: String?) throws -> CanonicalCalendarEventType? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard let type = CanonicalCalendarEventType.parse(trimmed) else {
      throw LorvexCoreError.validation(
        field: "event_type", message: "Unsupported calendar event type '\(trimmed)'.")
    }
    return type
  }

  static func patchEventType(_ value: String?) throws -> Patch<CanonicalCalendarEventType> {
    guard let type = try calendarEventType(value) else { return .unset }
    return .set(type)
  }

  static func attendeeInputs(_ attendees: [CalendarEventAttendee]?) -> [CalendarAttendeeInput]? {
    guard let attendees else { return nil }
    return attendees.map(attendeeInput)
  }

  static func patchAttendees(_ patch: CalendarEventAttendeesPatch) -> Patch<[CalendarAttendeeInput]> {
    switch patch {
    case .unset: return .unset
    case .clear: return .clear
    case .set(let attendees): return .set(attendees.map(attendeeInput))
    }
  }

  static func patchRecurrence(_ patch: CalendarEventRecurrencePatch) throws -> Patch<String> {
    switch patch {
    case .unset:
      return .unset
    case .clear:
      return .clear
    case .set(let rule):
      guard let canonical = rule.canonicalRecurrenceJSON() else {
        throw LorvexCoreError.validation(
          field: "recurrence", message: "The recurrence rule could not be serialized.")
      }
      return .set(canonical)
    }
  }

  /// Resolve the attendee list to carry onto a newly materialized occurrence replacement.
  /// `.unset` preserves the invoked event's current annotation by reading its
  /// `attendees` column; `.clear` drops it; `.set` uses the supplied list.
  static func resolvedCreateAttendees(
    _ db: Database, eventID: String, patch: CalendarEventAttendeesPatch
  ) throws -> [CalendarAttendeeInput]? {
    switch patch {
    case .unset:
      guard let row = try CalendarTimelineQueries.getCalendarEvent(db, id: eventID) else {
        return nil
      }
      return SwiftLorvexCalendarDeserializers.attendees(fromJSONString: row.attendees)?
        .map(attendeeInput)
    case .clear:
      return []
    case .set(let attendees):
      return attendees.map(attendeeInput)
    }
  }

  static func attendeeInput(_ attendee: CalendarEventAttendee) -> CalendarAttendeeInput {
    CalendarAttendeeInput(email: attendee.email, name: attendee.name)
  }
}
