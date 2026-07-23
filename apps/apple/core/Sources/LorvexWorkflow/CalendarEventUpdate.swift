import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Surface-agnostic calendar-event update input. Every nullable field carries
/// ``Patch`` so surfaces can express the three-state contract without a
/// side channel; `title` and `allDay` stay plain `Optional` because they
/// have no row-level "clear" state. `startDate` carries ``Patch`` for
/// surface symmetry but ``CalendarEventUpdate/updateCalendarEvent(_:hlc:input:before:beforeRecurrence:existing:)``
/// rejects ``Patch/clear`` with a validation error (the column is required).
///
/// `attendees: Patch<[CalendarAttendeeInput]>` carries replace-set semantics
/// for the `attendees` JSON column: ``Patch/unset`` leaves the column as-is,
/// ``Patch/clear`` writes NULL, ``Patch/set(_:)`` writes the serialized list
/// (an empty list collapses to the same effect as ``Patch/clear``).
public struct CalendarEventUpdateInput: Sendable, Equatable {
  public var id: String
  public var title: String?
  public var recurrence: Patch<String>
  public var timezone: Patch<String>
  public var startDate: Patch<String>
  public var startTime: Patch<String>
  public var endDate: Patch<String>
  public var endTime: Patch<String>
  public var allDay: Bool?
  public var description: Patch<String>
  public var location: Patch<String>
  public var url: Patch<String>
  public var color: Patch<String>
  public var eventType: Patch<CanonicalCalendarEventType>
  public var personName: Patch<String>
  public var attendees: Patch<[CalendarAttendeeInput]>
  /// Internal occurrence-register transition. Public generic updates leave this
  /// unset; the scoped coordinator uses it to move one deterministic decision
  /// between replacement / cancelled / inherit under the same row HLC.
  public var occurrenceState: Patch<CalendarOccurrenceState>
  /// Explicit `all_in_series` semantics: invalidate the current occurrence
  /// namespace even when the visible content patch is metadata-only.
  public var resetOccurrenceDecisions: Bool

  public init(
    id: String, title: String? = nil,
    recurrence: Patch<String> = .unset, timezone: Patch<String> = .unset,
    startDate: Patch<String> = .unset, startTime: Patch<String> = .unset,
    endDate: Patch<String> = .unset, endTime: Patch<String> = .unset,
    allDay: Bool? = nil, description: Patch<String> = .unset,
    location: Patch<String> = .unset, url: Patch<String> = .unset,
    color: Patch<String> = .unset,
    eventType: Patch<CanonicalCalendarEventType> = .unset,
    personName: Patch<String> = .unset,
    attendees: Patch<[CalendarAttendeeInput]> = .unset,
    occurrenceState: Patch<CalendarOccurrenceState> = .unset,
    resetOccurrenceDecisions: Bool = false
  ) {
    self.id = id
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
    self.attendees = attendees
    self.occurrenceState = occurrenceState
    self.resetOccurrenceDecisions = resetOccurrenceDecisions
  }
}

public struct UpdateCalendarEventResult: Sendable {
  public let eventId: String
  /// Pre-mutation row JSON snapshot — for ai_changelog `before_json`.
  public let before: JSONValue
  /// Post-mutation row JSON snapshot — the rich response.
  public let event: JSONValue
  public let summary: String
  public let dstGuard: CalendarDstGuard
  public let anchorShifted: Bool
}

/// Canonical calendar-event update orchestrator.
///
/// Owns the independent content/topology clocks on base events:
///
/// - `content_version` advances when descriptive content changes.
/// - `recurrence_topology_version` advances whenever timing, timezone, or the
///   recurrence rule changes, or an explicit generation reset is requested.
///   Inbound sync joins it with `content_version`, preserving concurrent edits
///   to either group.
/// - `recurrence_generation` advances only when the civil-date occurrence grid
///   changes (start-date / recurrence skeleton) or an explicit all-series reset
///   is requested. COUNT / UNTIL truncation preserves the generation, so valid
///   decisions on the surviving prefix remain active.
///
/// Occurrence decision rows own neither topology clock; their state and complete
/// materialized snapshot are one ordinary LWW value.
public enum CalendarEventUpdate {

  /// Execute a calendar-event update call.
  ///
  /// - `before`: pre-mutation row JSON snapshot, captured by the caller
  ///   via ``CalendarEventLoad/loadCalendarEventJSON(_:eventId:)`` before
  ///   opening the write savepoint. Surfaced verbatim on the result for
  ///   ai_changelog.
  /// - `beforeRecurrence`: raw RRULE / canonical recurrence JSON of the
  ///   existing row. Used to decide whether the occurrence grid changed.
  /// - `existing`: the pre-mutation effective fields used by
  ///   normalization for `Patch::Unset` reconciliation + the DST guard.
  public static func updateCalendarEvent(
    _ db: Database,
    hlc: HlcSession,
    input: CalendarEventUpdateInput,
    before: JSONValue,
    beforeRecurrence: String?,
    existing: CalendarUpdateExisting
  ) throws -> UpdateCalendarEventResult {
    // `start_date` is `Patch<String>` on the wire for surface symmetry;
    // the only row-level states are "leave as-is" and "re-anchor".
    let startDate: String?
    switch input.startDate {
    case .unset: startDate = nil
    case .set(let v): startDate = v
    case .clear:
      throw CalendarEventOpError.validation(
        "start_date cannot be cleared (use Patch::Set to re-anchor, "
          + "omit to leave alone)")
    }

    let normalized: NormalizedCalendarUpdate
    do {
      normalized = try CalendarNormalization.normalizeCalendarUpdate(
        CalendarUpdateInput(
          title: input.title, recurrence: input.recurrence,
          timezone: input.timezone, startDate: startDate,
          startTime: input.startTime, endDate: input.endDate,
          endTime: input.endTime, allDay: input.allDay,
          description: input.description, location: input.location,
          url: input.url, color: input.color, eventType: input.eventType,
          personName: input.personName),
        existing: existing)
    } catch let e as CalendarEventOpError {
      throw e
    }

    // Anchor-shift detection (start_date or start_time edits that move
    // every instance to a new grid). Routes around the recurrence-skeleton
    // comparator for cases where only the anchor moves.
    let anchorShifted = isAnchorShift(
      normalizedStartTime: normalized.startTime,
      beforeStartTime: existing.startTime,
      normalizedStartDate: normalized.startDate,
      beforeStartDate: existing.startDate)

    guard let stored = try CalendarTimelineQueries.getStoredCalendarEvent(db, id: input.id) else {
      throw CalendarEventOpError.store(
        .notFound(entity: EntityName.calendarEvent, id: input.id))
    }
    let effectiveRecurrence: String?
    switch normalized.recurrence {
    case .unset: effectiveRecurrence = stored.recurrence
    case .clear: effectiveRecurrence = nil
    case .set(let value): effectiveRecurrence = value
    }
    let version = try VersionFloor.mint(
      hlc: hlc,
      existingVersion: stored.version,
      entityType: EntityName.calendarEvent,
      entityId: input.id)
    let now = SyncTimestampFormat.syncTimestampNow()

    let isDecision = stored.seriesId != nil
    if isDecision, input.resetOccurrenceDecisions {
      throw CalendarEventOpError.validation(
        "an occurrence decision cannot reset its parent series generation")
    }

    // Compare prospective topology values, not merely patch presence: setting a
    // field to its current value remains a metadata no-op and must not mint a new
    // topology token (or invalidate a generation).
    let effective = normalized.effective
    let recurrenceChanged = effectiveRecurrence != stored.recurrence
    let topologyChanged =
      effective.startDate != existing.startDate
      || effective.startTime != existing.startTime
      || effective.endDate != existing.endDate
      || effective.endTime != existing.endTime
      || effective.allDay != existing.allDay
      || effective.timezone != existing.timezone
      || recurrenceChanged
      || input.resetOccurrenceDecisions

    let recurrenceGridChanged: Bool = {
      if effective.startDate != existing.startDate { return true }
      switch (beforeRecurrence, effectiveRecurrence) {
      case (nil, nil):
        return false
      case (.some, nil), (nil, .some):
        return true
      case let (.some(old), .some(new)):
        return !CalendarEventRecurrence.recurrenceSkeletonMatches(old, new)
      }
    }()

    let topologyVersionPatch: Patch<String>
    let generationPatch: Patch<String>
    if isDecision {
      topologyVersionPatch = .unset
      generationPatch = .unset
    } else {
      topologyVersionPatch = topologyChanged ? .set(version) : .unset
      if effectiveRecurrence == nil {
        generationPatch = stored.recurrenceGeneration == nil ? .unset : .clear
      } else if input.resetOccurrenceDecisions || recurrenceGridChanged
        || stored.recurrenceGeneration == nil
      {
        generationPatch = .set(version)
      } else {
        generationPatch = .unset
      }
    }

    let effectiveOccurrenceState = resolvePatch(
      input.occurrenceState, current: stored.occurrenceState)
    let effectiveGeneration = resolvePatch(
      generationPatch, current: stored.recurrenceGeneration)
    let effectiveTopologyVersion = resolvePatch(
      topologyVersionPatch, current: stored.recurrenceTopologyVersion)
    if case .failure(let error) = CalendarEventOccurrenceInvariant.validate(
      eventId: input.id,
      recurrence: effectiveRecurrence,
      seriesCutoverId: stored.seriesCutoverId,
      seriesId: stored.seriesId,
      recurrenceInstanceDate: stored.recurrenceInstanceDate,
      occurrenceState: effectiveOccurrenceState,
      recurrenceGeneration: effectiveGeneration,
      recurrenceTopologyVersion: effectiveTopologyVersion)
    {
      throw CalendarEventOpError.validation(error.description)
    }

    // Replace-set attendee semantics for the JSON column:
    //   - `.unset` — leave the column as-is.
    //   - `.clear` — write NULL.
    //   - `.set(list)` — write the serialized list (empty list collapses to NULL).
    // Validate + serialize BEFORE the write so a bad entry never half-applies.
    let attendeesPatch: Patch<String>
    switch input.attendees {
    case .unset:
      attendeesPatch = .unset
    case .clear:
      attendeesPatch = .clear
    case .set(let list):
      do {
        attendeesPatch = try CalendarEventAttendees.serialize(list).map(Patch.set) ?? .clear
      } catch let e as CalendarEventOpError {
        throw e.asStoreError()
      }
    }

    let effectiveTitle = normalized.title ?? stored.title
    let effectiveDescription = resolvePatch(
      normalized.description, current: stored.description)
    let effectiveLocation = resolvePatch(normalized.location, current: stored.location)
    let effectiveURL = resolvePatch(normalized.url, current: stored.url)
    let effectiveColor = resolvePatch(normalized.color, current: stored.color)
    let effectiveEventType = resolvePatch(normalized.eventType, current: stored.eventType)
    let effectivePersonName = resolvePatch(normalized.personName, current: stored.personName)
    let effectiveAttendees = resolvePatch(attendeesPatch, current: stored.attendees)
    let contentChanged =
      effectiveTitle != stored.title
      || effectiveDescription != stored.description
      || effectiveLocation != stored.location
      || effectiveURL != stored.url
      || effectiveColor != stored.color
      || effectiveEventType != stored.eventType
      || effectivePersonName != stored.personName
      || effectiveAttendees != stored.attendees
    let contentVersionPatch: Patch<String> =
      !isDecision && contentChanged ? .set(version) : .unset

    let patch = CalendarEventUpdatePatch(
      eventId: input.id,
      title: normalized.title,
      description: normalized.description,
      recurrence: normalized.recurrence,
      timezone: normalized.timezone,
      startDate: normalized.startDate,
      startTime: normalized.startTime,
      endDate: normalized.endDate,
      endTime: normalized.endTime,
      allDay: AllDayPatch.fromOptionalBool(normalized.allDay),
      location: normalized.location,
      url: normalized.url,
      color: normalized.color,
      eventType: mapPatch(normalized.eventType, transform: { $0.rawValue }),
      personName: normalized.personName,
      attendees: attendeesPatch,
      occurrenceState: input.occurrenceState,
      recurrenceGeneration: generationPatch,
      recurrenceTopologyVersion: topologyVersionPatch,
      contentVersion: contentVersionPatch,
      version: version,
      now: now)
    try CalendarEventWriteRepo.applyCalendarEventUpdate(db, patch: patch)

    guard let event = try CalendarEventLoad.loadCalendarEventJSON(db, eventId: input.id)
    else {
      throw StoreError.invariant(
        "calendar event \(input.id) disappeared after update")
    }
    let title: String = {
      if case .object(let m) = event, case .string(let s) = m["title"] ?? .null {
        return s
      }
      return "unknown"
    }()
    let summary = "Updated calendar event '\(title)'"

    return UpdateCalendarEventResult(
      eventId: input.id, before: before, event: event,
      summary: summary, dstGuard: normalized.dstGuard,
      anchorShifted: anchorShifted)
  }

  /// True when the patch shifts the event anchor (start_date or start_time)
  /// to a different wall-clock value. An anchor shift moves every generated
  /// instance to a new occurrence grid.
  /// `Patch::Set` with the same value is a no-op and is not a shift.
  static func isAnchorShift(
    normalizedStartTime: Patch<String>,
    beforeStartTime: String?,
    normalizedStartDate: String?,
    beforeStartDate: String
  ) -> Bool {
    let startTimeShifted: Bool
    switch normalizedStartTime {
    case .set(let v): startTimeShifted = (beforeStartTime != v)
    case .clear: startTimeShifted = (beforeStartTime != nil)
    case .unset: startTimeShifted = false
    }
    let startDateShifted: Bool
    if let v = normalizedStartDate {
      startDateShifted = (v != beforeStartDate)
    } else {
      startDateShifted = false
    }
    return startTimeShifted || startDateShifted
  }
}

@inline(__always)
private func mapPatch<T: Sendable, U: Sendable>(
  _ p: Patch<T>, transform: (T) -> U
) -> Patch<U> {
  switch p {
  case .unset: return .unset
  case .clear: return .clear
  case .set(let v): return .set(transform(v))
  }
}

@inline(__always)
private func resolvePatch<T: Sendable>(_ patch: Patch<T>, current: T?) -> T? {
  switch patch {
  case .unset: return current
  case .clear: return nil
  case .set(let value): return value
  }
}
