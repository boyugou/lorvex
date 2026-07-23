import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Result of ``CalendarEventCreate/createCalendarEvent(_:hlc:eventId:input:)``.
public struct CreateCalendarEventResult: Sendable {
  /// Event id that was written.
  public let eventId: String
  /// Post-mutation row + attendees, ready to surface as the rich response.
  public let event: JSONValue
  /// Human-readable audit summary ("Created calendar event 'Title'").
  public let summary: String
  /// DST guard surfaced by normalization. Surfaces consult this after
  /// `apply` to optionally append a diagnostic `error_log` row when the
  /// wall clock landed on an ambiguous fall-back hour.
  public let dstGuard: CalendarDstGuard
}

/// Canonical calendar-event create orchestrator.
///
/// Pipeline:
///
/// 1. Normalize + validate inputs via
///    ``CalendarNormalization/normalizeCalendarCreate(_:)`` (title hygiene,
///    URL allowlist, recurrence canonicalization with BYMONTHDAY injection,
///    field-shape + DST gates).
/// 2. Validate + serialize the attendee list via
///    ``CalendarEventAttendees/serialize(_:)`` into the `attendees` column JSON.
/// 3. Resolve the row's recurrence topology / occurrence-decision identity.
/// 4. INSERT the row via ``CalendarEventWriteRepo/createCalendarEvent(_:params:)``.
/// 5. Read back the enriched row via
///    ``CalendarEventLoad/loadCalendarEventJSON(_:eventId:)`` for the response.
///
/// The orchestrator presumes the caller has opened a write transaction
/// around the call. The caller drives the ``HlcSession`` — one HLC per
/// top-level mutation.
public enum CalendarEventCreate {

  /// Execute a calendar-event create call.
  ///
  /// - `eventId`: explicit event id. Mints elsewhere (the workflow surface
  ///   does not own id minting for calendar events).
  /// - `input`: the surface-agnostic create inputs, including optional
  ///   attendees.
  public static func createCalendarEvent(
    _ db: Database,
    hlc: HlcSession,
    eventId: String,
    input: CalendarEventCreateInput
  ) throws -> CreateCalendarEventResult {
    let normalized: NormalizedCalendarCreate
    do {
      normalized = try CalendarNormalization.normalizeCalendarCreate(
        CalendarCreateInput(
          title: input.title, recurrence: input.recurrence,
          timezone: input.timezone, startDate: input.startDate,
          startTime: input.startTime, endDate: input.endDate,
          endTime: input.endTime, allDay: input.allDay,
          description: input.description, location: input.location,
          url: input.url, color: input.color, eventType: input.eventType,
          personName: input.personName))
    } catch let e as CalendarEventOpError {
      throw e
    }

    let version = try VersionFloor.mint(
      hlc: hlc,
      existingVersion: input.recurrenceGeneration,
      entityType: EntityName.calendarEvent,
      entityId: eventId)
    let now = SyncTimestampFormat.syncTimestampNow()

    // A base event owns independent content and topology registers. New recurring
    // masters also open an occurrence-decision generation; ordinary plain events
    // do not. A decision row supplies its master's generation and deliberately
    // owns neither register — its state + materialized snapshot are one LWW value.
    // When a generation is supplied, the row version was minted strictly above
    // it so the aggregate high-water invariant also holds for decision rows.
    let recurrenceGeneration: String?
    let recurrenceTopologyVersion: String?
    let contentVersion: String?
    if input.seriesId != nil {
      recurrenceGeneration = input.recurrenceGeneration
      recurrenceTopologyVersion = nil
      contentVersion = nil
    } else {
      recurrenceGeneration = normalized.recurrence == nil
        ? nil : (input.recurrenceGeneration ?? version)
      recurrenceTopologyVersion = version
      contentVersion = version
    }
    if case .failure(let error) = CalendarEventOccurrenceInvariant.validate(
      eventId: eventId,
      recurrence: normalized.recurrence,
      seriesCutoverId: input.seriesCutoverId,
      seriesId: input.seriesId,
      recurrenceInstanceDate: input.recurrenceInstanceDate,
      occurrenceState: input.occurrenceState,
      recurrenceGeneration: recurrenceGeneration,
      recurrenceTopologyVersion: recurrenceTopologyVersion)
    {
      throw CalendarEventOpError.validation(error.description)
    }

    // Validate + serialize attendees BEFORE the INSERT so a bad entry never
    // half-writes the event row.
    let attendeesJSON: String?
    do {
      attendeesJSON = try CalendarEventAttendees.serialize(input.attendees ?? [])
    } catch let e as CalendarEventOpError {
      throw e.asStoreError()
    }

    try CalendarEventWriteRepo.createCalendarEvent(
      db,
      params: CalendarEventCreateParams(
        id: eventId,
        title: normalized.title,
        description: normalized.description,
        recurrence: normalized.recurrence,
        timezone: normalized.timezone,
        startDate: normalized.startDate,
        startTime: normalized.startTime,
        endDate: normalized.endDate,
        endTime: normalized.endTime,
        allDay: normalized.allDay,
        location: normalized.location,
        url: normalized.url,
        color: normalized.color,
        eventType: normalized.eventType.rawValue,
        personName: normalized.personName,
        attendees: attendeesJSON,
        seriesCutoverId: input.seriesCutoverId,
        seriesId: input.seriesId,
        recurrenceInstanceDate: input.recurrenceInstanceDate,
        occurrenceState: input.occurrenceState,
        recurrenceGeneration: recurrenceGeneration,
        recurrenceTopologyVersion: recurrenceTopologyVersion,
        contentVersion: contentVersion,
        version: version,
        now: now))

    guard let event = try CalendarEventLoad.loadCalendarEventJSON(db, eventId: eventId)
    else {
      throw StoreError.invariant(
        "calendar event \(eventId) disappeared after insert")
    }
    let title: String = {
      if case .object(let m) = event, case .string(let s) = m["title"] ?? .null {
        return s
      }
      return "unknown"
    }()
    let summary = "Created calendar event '\(title)'"

    return CreateCalendarEventResult(
      eventId: eventId, event: event, summary: summary,
      dstGuard: normalized.dstGuard)
  }
}

/// Surface-agnostic calendar-event create input.
public struct CalendarEventCreateInput: Sendable, Equatable {
  public var title: String
  public var recurrence: String?
  public var timezone: String?
  public var startDate: String
  public var startTime: String?
  public var endDate: String?
  public var endTime: String?
  public var allDay: Bool?
  public var description: String?
  public var location: String?
  public var url: String?
  public var color: String?
  public var eventType: CanonicalCalendarEventType?
  public var personName: String?
  /// Deterministic boundary identity for a recurring-series tail segment.
  /// It equals the segment event id. Ordinary base events and occurrence
  /// decisions leave it nil.
  public var seriesCutoverId: String?
  /// Occurrence-decision linkage to a recurring series master. A decision sets
  /// all four fields; a recurring master owns `recurrenceGeneration`; a plain
  /// event leaves the generation nil. Base-event content/topology clocks are
  /// always derived from the newly minted row version.
  public var seriesId: String?
  public var recurrenceInstanceDate: String?
  public var occurrenceState: CalendarOccurrenceState?
  public var recurrenceGeneration: String?
  public var attendees: [CalendarAttendeeInput]?

  public init(
    title: String, recurrence: String? = nil, timezone: String? = nil,
    startDate: String, startTime: String? = nil, endDate: String? = nil,
    endTime: String? = nil, allDay: Bool? = nil, description: String? = nil,
    location: String? = nil, url: String? = nil, color: String? = nil,
    eventType: CanonicalCalendarEventType? = nil, personName: String? = nil,
    seriesCutoverId: String? = nil,
    seriesId: String? = nil, recurrenceInstanceDate: String? = nil,
    occurrenceState: CalendarOccurrenceState? = nil,
    recurrenceGeneration: String? = nil,
    attendees: [CalendarAttendeeInput]? = nil
  ) {
    self.title = title
    self.recurrence = recurrence
    self.timezone = timezone
    self.startDate = startDate
    self.startTime = startTime
    self.endDate = endDate
    self.endTime = endTime
    self.allDay = allDay
    self.description = description
    self.location = location
    self.url = url
    self.color = color
    self.eventType = eventType
    self.personName = personName
    self.seriesCutoverId = seriesCutoverId
    self.seriesId = seriesId
    self.recurrenceInstanceDate = recurrenceInstanceDate
    self.occurrenceState = occurrenceState
    self.recurrenceGeneration = recurrenceGeneration
    self.attendees = attendees
  }
}
