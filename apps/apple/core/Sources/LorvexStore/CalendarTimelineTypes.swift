import Foundation
import LorvexDomain

/// Output types for calendar-timeline queries.
public enum CalendarTimeline {}

/// Whether an event originates from Lorvex's own `calendar_events` table or
/// from an external provider (Apple Calendar, Google Calendar, …).
public enum TimelineSource: String, Sendable, Equatable {
  case canonical
  case provider
}

/// A single occurrence on a calendar timeline (post-expansion).
///
/// Recurring events are expanded into individual items before reaching this
/// type, so it carries no recurrence / recurrence_exceptions fields. The
/// `(start_date, start_time, end_date, end_time, all_day)` quintuple is
/// bundled into a typed ``CalendarEventTiming`` so illegal combinations are
/// non-representable.
public struct CalendarTimelineItem: Sendable, Equatable {
  public var source: TimelineSource
  public var editable: Bool
  /// Stable occurrence identity, or composite `"kind:scope:key"` for provider
  /// events. A recurring canonical occurrence uses its deterministic decision
  /// UUID even before a decision row exists.
  public var id: String
  /// Stable source event address. Expansion changes ``id`` per occurrence for
  /// SwiftUI identity while this stays at the canonical series id or provider
  /// `"kind:scope:key"`. Canonical mutation/link tools accept the former;
  /// device-local provider-link tools accept the latter with its provider kind.
  public var eventId: String
  public var title: String
  public var timing: CalendarEventTiming
  public var location: String?
  public var color: String?
  public var eventType: String
  public var personName: String?
  public var timezone: String?
  public var providerKind: String?
  public var providerScope: String?
  public var isRecurring: Bool
  public var recurrenceRule: String?
  public var sourceTimeKind: String?
  public var sourceTzid: String?
  public var url: String?
  public var attendeesJson: String?
  /// Free-text notes (the `description` column on `calendar_events`); nil for
  /// provider mirror occurrences, which don't expose notes here.
  public var description: String?
  /// Recurring-series master id for canonical occurrences and replacement
  /// decisions; nil for plain and provider events.
  public var seriesId: String?
  /// Original occurrence date within the series grid.
  public var recurrenceInstanceDate: String?
  /// Generation that namespaces the occurrence decision identity.
  public var recurrenceGeneration: String?
  /// Non-nil only for a visible stored replacement. Natural expanded
  /// occurrences have no decision state; cancelled and inherit rows are hidden.
  public var occurrenceState: CalendarOccurrenceState?

  public var startDate: LorvexDate { timing.startDate }
  public var startTime: TimeOfDay? { timing.startTime }
  public var endDate: LorvexDate? { timing.endDate }
  public var endTime: TimeOfDay? { timing.endTime }
  public var allDay: Bool { timing.allDay }

  /// Build an item, enforcing temporal validity via
  /// ``CalendarEventTiming/fromFlatFields(startDate:startTime:endDate:endTime:allDay:)``.
  public static func make(
    source: TimelineSource, editable: Bool, id: String, title: String,
    startDate: LorvexDate, startTime: TimeOfDay?, endDate: LorvexDate?,
    endTime: TimeOfDay?, allDay: Bool, location: String?, color: String?,
    eventType: String, personName: String?, timezone: String?,
    providerKind: String?, providerScope: String?, isRecurring: Bool,
    recurrenceRule: String? = nil, sourceTimeKind: String?, sourceTzid: String?,
    url: String?, attendeesJson: String?, description: String? = nil,
    seriesId: String? = nil, recurrenceInstanceDate: String? = nil,
    recurrenceGeneration: String? = nil,
    occurrenceState: CalendarOccurrenceState? = nil
  ) -> Result<CalendarTimelineItem, ValidationError> {
    CalendarEventTiming.fromFlatFields(
      startDate: startDate, startTime: startTime, endDate: endDate,
      endTime: endTime, allDay: allDay
    ).map { timing in
      CalendarTimelineItem(
        source: source, editable: editable, id: id, eventId: seriesId ?? id,
        title: title, timing: timing,
        location: location, color: color, eventType: eventType, personName: personName,
        timezone: timezone, providerKind: providerKind, providerScope: providerScope,
        isRecurring: isRecurring, recurrenceRule: recurrenceRule, sourceTimeKind: sourceTimeKind,
        sourceTzid: sourceTzid, url: url, attendeesJson: attendeesJson, description: description,
        seriesId: seriesId, recurrenceInstanceDate: recurrenceInstanceDate,
        recurrenceGeneration: recurrenceGeneration, occurrenceState: occurrenceState)
    }
  }
}

/// A time range that blocks scheduling within a single day.
public struct BlockingEventRange: Sendable, Equatable {
  public var source: TimelineSource
  /// `Some(id)` only for canonical events.
  public var canonicalEventId: String?
  public var title: String
  /// Minutes from midnight (start of the blocking window).
  public var startMinutes: Int64
  /// Minutes from midnight (end of the blocking window).
  public var endMinutes: Int64
  /// True if the provider data backing this range may be stale.
  public var stale: Bool
}

/// A row read directly from the `calendar_events` table (no expansion).
///
/// Used by text-search queries that return canonical events as stored,
/// without recurrence expansion or timezone projection.
public struct CalendarEventRow: Sendable, Equatable {
  public var id: String
  public var title: String
  public var description: String?
  public var recurrence: String?
  public var recurrenceExceptions: String?
  public var timezone: String?
  public var timing: CalendarEventTiming
  public var location: String?
  public var color: String?
  public var eventType: CanonicalCalendarEventType
  public var personName: String?
  public var url: String?
  /// Raw `calendar_events.attendees` JSON text (a JSON array of `{name?, email?}`
  /// objects), or nil when the event has no attendees. Deserialized by the
  /// surface layer; the store carries it verbatim.
  public var attendees: String?
  /// Deterministic cutover identity for a recurring tail segment. Root/plain
  /// events and occurrence decisions leave this nil.
  public var seriesCutoverId: String?
  /// Decision-linkage group id (the originating series master's event id), or
  /// nil for a base event.
  public var seriesId: String?
  /// The original `YYYY-MM-DD` occurrence addressed by this decision.
  public var recurrenceInstanceDate: String?
  public var occurrenceState: CalendarOccurrenceState?
  public var recurrenceGeneration: String?
  public var recurrenceTopologyVersion: String?
  /// Independent descriptive-content register on base rows. Occurrence
  /// decisions are whole-row LWW and leave this nil.
  public var contentVersion: String?
  public var createdAt: String
  public var updatedAt: String
  public var version: String

  public var startDate: LorvexDate { timing.startDate }
  public var startTime: TimeOfDay? { timing.startTime }
  public var endDate: LorvexDate? { timing.endDate }
  public var endTime: TimeOfDay? { timing.endTime }
  public var allDay: Bool { timing.allDay }
}
