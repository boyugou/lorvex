import Foundation

public struct CalendarTimelineSnapshot: Equatable, Sendable {
  public var from: String
  public var to: String
  public var events: [CalendarTimelineEvent]
  public var truncated: Bool
  public var nextOffset: Int?

  public init(
    from: String,
    to: String,
    events: [CalendarTimelineEvent],
    truncated: Bool,
    nextOffset: Int?
  ) {
    self.from = from
    self.to = to
    self.events = events
    self.truncated = truncated
    self.nextOffset = nextOffset
  }
}

/// Represents a task <-> calendar-event association.
///
/// `providerEventID` is nil for canonical (Lorvex-owned) event links and
/// set to the provider's stable identifier (e.g. EventKit UUID) for
/// provider-event links. `providerSource` names the provider (`"eventkit"`)
/// and is nil for canonical links.
public struct TaskCalendarEventLink: Equatable, Sendable {
  public var taskID: String
  public var eventID: String
  public var providerEventID: String?
  public var providerSource: String?

  public init(
    taskID: String,
    eventID: String,
    providerEventID: String? = nil,
    providerSource: String? = nil
  ) {
    self.taskID = taskID
    self.eventID = eventID
    self.providerEventID = providerEventID
    self.providerSource = providerSource
  }
}

/// A calendar-event attendee display projection, shared by Lorvex-native events
/// and read-only EventKit provider events.
///
/// `email` is `""` when the entry carries only a name; at least one of email /
/// name is non-empty. `status` is the RFC 5545 PARTSTAT (`accepted` / `declined`
/// / `tentative` / `needs-action`) and is populated ONLY for provider events
/// (from `provider_calendar_events.attendees_json`); Lorvex-native attendees are
/// a lightweight `{name?, email?}` annotation with no RSVP state, so they leave
/// `status` nil and never accept it on input.
public struct CalendarEventAttendee: Codable, Equatable, Sendable {
  public var email: String
  public var name: String?
  public var status: String?

  public init(email: String, name: String? = nil, status: String? = nil) {
    self.email = email
    self.name = name
    self.status = status
  }
}

public enum CalendarEventAttendeesPatch: Equatable, Sendable {
  case unset
  case clear
  case set([CalendarEventAttendee])
}

/// Three-state recurrence patch for calendar updates. Creation uses an optional
/// rule because there is no existing value; updates must distinguish omission
/// from an explicit request to stop repeating.
public enum CalendarEventRecurrencePatch: Equatable, Sendable {
  case unset
  case clear
  case set(TaskRecurrenceRule)
}

public enum CalendarTimelineOccurrenceState: String, Equatable, Sendable {
  case replacement
  case cancelled
  case inherit
}

public struct CalendarTimelineEvent: Identifiable, Equatable, Sendable {
  /// Stable identity for this rendered occurrence. Recurring series therefore
  /// expose a different id for every expanded occurrence.
  public var id: String
  /// Stable source event address. For a canonical expanded occurrence this is
  /// the recurring series master's id; for a canonical one-off it equals
  /// ``id``; provider rows carry their composite device-local source address.
  public var eventID: String
  public var seriesID: String?
  public var recurrenceGeneration: String?
  /// The original recurrence slot (`YYYY-MM-DD`) addressed by a scoped edit.
  /// This deliberately remains unchanged when a replacement moves to another
  /// display date.
  public var occurrenceDate: String?
  public var occurrenceState: CalendarTimelineOccurrenceState?
  /// True when this event belongs to a recurring-series workflow, including a
  /// visible one-off replacement whose own recurrence rule is nil.
  public var supportsScopedMutation: Bool
  public var title: String
  public var source: String
  public var editable: Bool
  public var startDate: String
  public var startTime: String?
  public var endDate: String?
  public var endTime: String?
  public var allDay: Bool
  public var location: String?
  /// Free-text event notes (the `description` column on `calendar_events`).
  /// Nil when the event has no notes, or for provider events whose source
  /// carries no description.
  public var notes: String?
  public var url: String?
  public var color: String?
  public var eventType: String
  public var personName: String?
  public var attendees: [CalendarEventAttendee]?
  public var timezone: String?
  public var isRecurring: Bool
  public var recurrenceRule: String?
  /// Human-readable summary of the primary recurrence rule, populated only
  /// for EventKit-sourced events. Nil when `isRecurring` is false or the rule
  /// cannot be summarized.
  public var recurrenceSummary: String?

  public init(
    id: String,
    eventID: String? = nil,
    seriesID: String? = nil,
    recurrenceGeneration: String? = nil,
    occurrenceDate: String? = nil,
    occurrenceState: CalendarTimelineOccurrenceState? = nil,
    supportsScopedMutation: Bool? = nil,
    title: String,
    source: String,
    editable: Bool,
    startDate: String,
    startTime: String?,
    endDate: String?,
    endTime: String?,
    allDay: Bool,
    location: String?,
    notes: String? = nil,
    url: String? = nil,
    color: String?,
    eventType: String,
    personName: String? = nil,
    attendees: [CalendarEventAttendee]? = nil,
    timezone: String?,
    isRecurring: Bool,
    recurrenceRule: String? = nil,
    recurrenceSummary: String? = nil
  ) {
    self.id = id
    self.eventID = eventID ?? seriesID ?? id
    self.seriesID = seriesID
    self.recurrenceGeneration = recurrenceGeneration
    let scoped = supportsScopedMutation ?? (editable && (isRecurring || seriesID != nil))
    self.occurrenceDate = occurrenceDate ?? (scoped ? startDate : nil)
    self.occurrenceState = occurrenceState
    self.supportsScopedMutation = scoped
    self.title = title
    self.source = source
    self.editable = editable
    self.startDate = startDate
    self.startTime = startTime
    self.endDate = endDate
    self.endTime = endTime
    self.allDay = allDay
    self.location = location
    self.notes = notes
    self.url = url
    self.color = color
    self.eventType = eventType
    self.personName = personName
    self.attendees = attendees
    self.timezone = timezone
    self.isRecurring = isRecurring
    self.recurrenceRule = recurrenceRule
    self.recurrenceSummary = recurrenceSummary
  }
}

/// Patch fields for a scoped calendar event edit. All fields are optional —
/// omitted fields preserve the original value.
public struct ScopedCalendarEventUpdates: Sendable {
  public var title: String?
  public var startDate: String?
  public var endDate: String?
  public var startTime: String?
  public var endTime: String?
  public var allDay: Bool?
  public var location: String?
  public var notes: String?
  public var recurrence: CalendarEventRecurrencePatch
  public var timezone: String?
  public var url: String?
  public var color: String?
  public var eventType: String?
  public var personName: String?
  public var attendees: CalendarEventAttendeesPatch

  public init(
    title: String? = nil, startDate: String? = nil, endDate: String? = nil,
    startTime: String? = nil, endTime: String? = nil, allDay: Bool? = nil,
    location: String? = nil, notes: String? = nil,
    recurrence: CalendarEventRecurrencePatch = .unset,
    timezone: String? = nil, url: String? = nil, color: String? = nil,
    eventType: String? = nil, personName: String? = nil,
    attendees: CalendarEventAttendeesPatch = .unset
  ) {
    self.title = title
    self.startDate = startDate
    self.endDate = endDate
    self.startTime = startTime
    self.endTime = endTime
    self.allDay = allDay
    self.location = location
    self.notes = notes
    self.recurrence = recurrence
    self.timezone = timezone
    self.url = url
    self.color = color
    self.eventType = eventType
    self.personName = personName
    self.attendees = attendees
  }
}

/// Result of a scoped calendar event edit.
public struct ScopedCalendarEventEditResult: Sendable {
  /// Canonical series-master id affected by the operation. When the caller
  /// addressed a materialized replacement decision this intentionally differs
  /// from that decision's id and lets mirror layers update/remove the real series.
  public var seriesID: String?
  public var originalEvent: CalendarTimelineEvent?
  public var replacementEvent: CalendarTimelineEvent?
  /// Materialized replacement-decision rows made obsolete by the operation. Mirror
  /// layers use these ids to remove their corresponding one-off artifacts only
  /// after any surviving/replacement series has been written successfully.
  public var invalidatedReplacementEventIDs: [String]
  public var noop: Bool

  public init(
    seriesID: String? = nil,
    originalEvent: CalendarTimelineEvent? = nil,
    replacementEvent: CalendarTimelineEvent? = nil,
    invalidatedReplacementEventIDs: [String] = [],
    noop: Bool = false
  ) {
    self.seriesID = seriesID
    self.originalEvent = originalEvent
    self.replacementEvent = replacementEvent
    self.invalidatedReplacementEventIDs = invalidatedReplacementEventIDs
    self.noop = noop
  }
}

/// Result of a scoped calendar event delete.
public struct ScopedCalendarEventDeleteResult: Sendable {
  public var seriesID: String?
  public var event: CalendarTimelineEvent?
  /// Materialized replacement-decision rows made obsolete by the delete scope.
  public var invalidatedReplacementEventIDs: [String]
  public var noop: Bool

  public init(
    seriesID: String? = nil,
    event: CalendarTimelineEvent? = nil,
    invalidatedReplacementEventIDs: [String] = [],
    noop: Bool = false
  ) {
    self.seriesID = seriesID
    self.event = event
    self.invalidatedReplacementEventIDs = invalidatedReplacementEventIDs
    self.noop = noop
  }
}
