import Foundation
import LorvexDomain

/// Platform-neutral projection of a system-calendar event fetched from
/// EventKit. The Apple app maps an `EKEvent` into this struct at the device
/// boundary; the pure ingest mapper below consumes it so the tier-redaction
/// contract is unit-testable without an `EKEventStore`.
///
/// `key` is the stable provider event identity (the app prefers
/// `calendarItemExternalIdentifier`, falling back to `eventIdentifier`); it
/// becomes the `provider_event_key` composite-key field. Dates/times are
/// already rendered to the canonical wire forms (`yyyy-MM-dd`, `HH:mm`) in the
/// active calendar's timezone so this layer holds no `Date` formatting.
public struct EventKitFetchedEvent: Sendable, Equatable {
  public let key: String
  public let title: String?
  public let notes: String?
  public let startDate: String
  public let startTime: String?
  public let endDate: String?
  public let endTime: String?
  public let allDay: Bool
  public let location: String?
  public let timezone: String?
  public let recurrence: String?
  public let recurrenceExceptions: String?
  /// `#RRGGBB` color of the event's source calendar, so the timeline can tint
  /// each event by its origin calendar (matching Apple Calendar) instead of one
  /// uniform accent. Occupancy-neutral, so it is preserved in busy-only tier.
  public let color: String?
  /// Meeting organizer's email, mapped from `EKEvent.organizer` at the device
  /// boundary. Private detail: mirrored only in the full-details tier.
  public let organizerEmail: String?
  /// The event's associated URL (e.g. a video-call link), mapped from
  /// `EKEvent.url` at the device boundary and stored in `video_call_url`.
  /// Private detail: mirrored only in the full-details tier.
  public let url: String?
  /// Meeting participants, mapped from `EKEvent.attendees` at the device
  /// boundary with `status` already normalized to the canonical RFC 5545
  /// PARTSTAT subset. Private detail: serialized into `attendees_json` only in
  /// the full-details tier.
  public let attendees: [EventKitFetchedAttendee]

  public init(
    key: String, title: String?, notes: String?,
    startDate: String, startTime: String?,
    endDate: String?, endTime: String?,
    allDay: Bool, location: String?, timezone: String?,
    recurrence: String? = nil, recurrenceExceptions: String? = nil,
    color: String? = nil, organizerEmail: String? = nil,
    url: String? = nil,
    attendees: [EventKitFetchedAttendee] = []
  ) {
    self.key = key
    self.title = title
    self.notes = notes
    self.startDate = startDate
    self.startTime = startTime
    self.endDate = endDate
    self.endTime = endTime
    self.allDay = allDay
    self.location = location
    self.timezone = timezone
    self.recurrence = recurrence
    self.recurrenceExceptions = recurrenceExceptions
    self.color = color
    self.organizerEmail = organizerEmail
    self.url = url
    self.attendees = attendees
  }
}

/// Platform-neutral projection of one system-calendar event attendee. The Apple
/// app maps an `EKParticipant` into this at the device boundary; `status` is
/// already the canonical RFC 5545 PARTSTAT subset (``AttendeeStatus``) so the
/// pure ingest serializer needs no EventKit vocabulary.
public struct EventKitFetchedAttendee: Sendable, Equatable {
  public let email: String
  public let name: String?
  public let status: AttendeeStatus?

  public init(email: String, name: String? = nil, status: AttendeeStatus? = nil) {
    self.email = email
    self.name = name
    self.status = status
  }
}

/// Pure EventKit-ingest mapping. Translates fetched system-calendar events into
/// `provider_calendar_events` upsert rows, enforcing the `CalendarAiAccessMode`
/// tier **at ingest** (not merely at the read/display layer) so redacted detail
/// never enters the local mirror:
///
/// - ``CalendarAiAccessMode/off``: returns `[]` — nothing is mirrored.
/// - ``CalendarAiAccessMode/busyOnly``: occupancy only. Title becomes the
///   generic `"Busy"`; location, notes/description, and timezone-free detail
///   are dropped. Start/end/all-day occupancy is preserved verbatim.
/// - ``CalendarAiAccessMode/fullDetails``: title, location, notes, organizer,
///   attendees, and the event URL pass through verbatim.
///
/// All rows carry `provider_kind = eventkit`. `scope` is the caller's provider
/// scope (a single device-wide scope by default). The read-layer redaction in
/// ``CalendarTimelineQueries/redactProviderDetails`` remains as defense in
/// depth; this function is the authoritative enforcement point.
public enum EventKitIngest {
  /// The generic title used for `busyOnly`-tier occupancy rows.
  public static let busyTitle = "Busy"

  public static func providerRows(
    from events: [EventKitFetchedEvent],
    scope: String,
    accessMode: CalendarAiAccessMode
  ) -> [ProviderEventData] {
    guard accessMode.includesProvider else { return [] }
    let full = accessMode.includesDetails
    return events.map { event in
      // Timezone is occupancy-relevant (it fixes the wall-clock projection), so
      // it is preserved in BOTH tiers. `tzid` + `source_tzid` lets the timeline
      // projection place a timed event in its origin zone; without a timezone
      // it falls back to floating semantics (see CalendarTimeline.temporalSemantics).
      let hasZone = !event.allDay && event.startTime != nil && event.timezone != nil
      return ProviderEventData(
        providerKind: ProviderKind.eventkit,
        providerScope: scope,
        providerEventKey: event.key,
        // A titleless system event (creatable in Apple Calendar) folds to nil
        // at the fetch boundary; coalesce the "(untitled)" fallback here so the
        // schema's NOT NULL `title` column never sees NULL and aborts the whole
        // single-transaction refresh.
        title: full ? (event.title ?? "(untitled)") : busyTitle,
        description: full ? event.notes : nil,
        startDate: event.startDate,
        startTime: event.startTime,
        endDate: event.endDate,
        endTime: event.endTime,
        allDay: event.allDay,
        location: full ? event.location : nil,
        organizerEmail: full ? event.organizerEmail : nil,
        sourceTimeKind: hasZone ? "tzid" : "floating",
        sourceTzid: hasZone ? event.timezone : nil,
        recurrence: event.recurrence,
        recurrenceExceptions: event.recurrenceExceptions,
        // The source-calendar color is occupancy-neutral metadata (it reveals
        // which calendar, not the event's content), so it passes through in both
        // the full and busy-only tiers.
        color: event.color,
        attendeesJson: full ? attendeesJSON(from: event.attendees) : nil,
        videoCallUrl: full ? event.url : nil)
    }
  }

  /// Serialize fetched attendees into the canonical `attendees_json` wire shape
  /// the timeline read path expects: a JSON array of
  /// `{"email":…, "name":…, "status":…}` objects — `name`/`status` omitted when
  /// absent, `status` rendered as the canonical RFC 5545 PARTSTAT string
  /// (`accepted` / `declined` / `tentative` / `needs-action`).
  ///
  /// Returns `nil` for an empty attendee list (the "no attendees → NULL column"
  /// contract) or if canonical serialization fails.
  static func attendeesJSON(from attendees: [EventKitFetchedAttendee]) -> String? {
    guard !attendees.isEmpty else { return nil }
    let array = JSONValue.array(
      attendees.map { attendee in
        var object: [String: JSONValue] = ["email": .string(attendee.email)]
        if let name = attendee.name { object["name"] = .string(name) }
        if let status = attendee.status { object["status"] = .string(status.asString) }
        return .object(object)
      })
    return try? canonicalizeJSON(array)
  }
}
