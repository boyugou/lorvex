import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// Per-scope recurring calendar mutations.
///
/// A single occurrence is one deterministic LWW decision row. Editing,
/// cancelling, and restoring that occurrence update the same row between
/// `replacement`, `cancelled`, and `inherit`; there is no second master-row
/// EXDATE write whose CloudKit arrival order could diverge.
extension SwiftLorvexCoreService {
  private struct ScopedResolvedTiming {
    var startDate: String
    var startTime: String?
    var endDate: String?
    var endTime: String?
    var allDay: Bool
  }

  private struct CalendarSeriesContext {
    var invoked: CalendarEventRow
    var master: CalendarEventRow
    var decision: CalendarEventRow?
    var source: CalendarEventRow
    var ownership: CalendarSeriesOwnership
  }

  /// The first real occurrence in this segment's ownership interval. A cutover
  /// is only a lineage partition boundary: moving a tail can put that date off
  /// the tail's own recurrence grid. Conversely, a tail moved before its lower
  /// boundary may not become visible until a later recurrence slot. Use the
  /// shared recurrence engine, then require the candidate to stay below the
  /// next boundary.
  private static func segmentFirstOccurrenceDate(
    master: CalendarEventRow,
    ownership: CalendarSeriesOwnership
  ) throws -> String? {
    guard let recurrence = master.recurrence else { return nil }
    let lowerBound = max(
      master.startDate.asString,
      ownership.lowerBoundCutoverDate ?? master.startDate.asString)
    let first = try CalendarRecurrence.firstOccurrenceOnOrAfter(
      recurrenceJson: recurrence,
      baseDateYmd: master.startDate.asString,
      targetDateYmd: lowerBound)
    guard let first, ownership.owns(recurrenceInstanceDate: first) else {
      return nil
    }
    return first
  }

  private static func resolvedScopedTiming(
    row: CalendarEventRow,
    defaultStartDate: String,
    updates: ScopedCalendarEventUpdates
  ) -> ScopedResolvedTiming {
    let startDate = updates.startDate ?? defaultStartDate
    let allDay = updates.allDay ?? row.allDay
    let startTime = allDay ? nil : (updates.startTime ?? row.startTime?.asString)
    let sourceDaySpan = calendarDaySpan(
      from: row.startDate.asString, to: row.endDate?.asString)
    var endDate =
      updates.endDate
      ?? shiftedEndDate(
        from: startDate, daySpan: sourceDaySpan)
    var endTime = allDay ? nil : (updates.endTime ?? row.endTime?.asString)

    let startMoved =
      updates.startDate != nil || updates.startTime != nil
      || defaultStartDate != row.startDate.asString
    if !allDay, startMoved, updates.endDate == nil, updates.endTime == nil,
      let oldStart = row.startTime, let oldEnd = row.endTime,
      let startTime, case .success(let newStart) = TimeOfDay.parse(startTime)
    {
      let duration =
        sourceDaySpan * 24 * 60
        + oldEnd.minutesOfDay - oldStart.minutesOfDay
      if duration >= 0 {
        let total = newStart.minutesOfDay + duration
        endTime = TimeOfDay.fromMinutesSaturating(total % (24 * 60)).asString
        endDate = shiftedEndDate(from: startDate, daySpan: total / (24 * 60))
      }
    }

    return ScopedResolvedTiming(
      startDate: startDate, startTime: startTime,
      endDate: endDate, endTime: endTime, allDay: allDay)
  }

  private static func calendarDaySpan(from start: String, to end: String?) -> Int {
    guard let end,
      let startDate = LorvexDateFormatters.ymdUTC.date(from: start),
      let endDate = LorvexDateFormatters.ymdUTC.date(from: end)
    else { return 0 }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return max(0, calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0)
  }

  private static func shiftedEndDate(from start: String, daySpan: Int) -> String? {
    guard daySpan > 0 else { return nil }
    return LorvexDateFormatters.ymdUTCAddingDays(start, days: daySpan)
  }

  private static func replacementPatch<T: Sendable>(_ value: T?) -> Patch<T> {
    value.map(Patch.set) ?? .clear
  }

  private static func validateInvokedDecision(
    _ invoked: CalendarEventRow, master: CalendarEventRow, occurrenceDate: String
  ) throws {
    guard invoked.seriesId != nil else { return }
    guard invoked.recurrenceInstanceDate == occurrenceDate else {
      throw LorvexCoreError.validation(
        field: "occurrence_date",
        message: "The addressed decision represents a different occurrence.")
    }
    guard invoked.recurrenceGeneration == master.recurrenceGeneration else {
      throw LorvexCoreError.validation(
        field: "event_id",
        message: "The addressed occurrence belongs to an obsolete series generation.")
    }
  }

  private static func seriesContext(
    _ db: Database, eventID: String, occurrenceDate: String
  ) throws -> CalendarSeriesContext {
    guard let invoked = try CalendarTimelineQueries.getStoredCalendarEvent(db, id: eventID) else {
      throw LorvexCoreError.notFound(entity: .calendarEvent, id: eventID)
    }
    guard
      let ownership = try CalendarTimelineQueries.getCalendarSeriesOwnership(
        db, eventId: eventID)
    else {
      throw LorvexCoreError.notFound(entity: .calendarSeries, id: eventID)
    }
    guard ownership.isActive else {
      throw LorvexCoreError.validation(
        field: "event_id", message: "The addressed calendar-series segment is deleted.")
    }
    guard ownership.owns(recurrenceInstanceDate: occurrenceDate) else {
      throw LorvexCoreError.validation(
        field: "occurrence_date",
        message: "The addressed segment does not own this occurrence date.")
    }
    let seriesId = ownership.segmentEventId
    guard let master = try CalendarTimelineQueries.getStoredCalendarEvent(db, id: seriesId) else {
      throw LorvexCoreError.notFound(entity: .calendarSeries, id: seriesId)
    }
    try validateSeriesOccurrence(master, occurrenceDate: occurrenceDate)
    try validateInvokedDecision(invoked, master: master, occurrenceDate: occurrenceDate)
    guard let generation = master.recurrenceGeneration else {
      throw LorvexCoreError.unsupportedOperation(
        "Recurring calendar series '\(seriesId)' has no occurrence generation.")
    }
    let decisionID = CalendarOccurrenceDecisionID.make(
      seriesId: seriesId,
      recurrenceGeneration: generation,
      recurrenceInstanceDate: occurrenceDate)
    let decision = try CalendarTimelineQueries.getStoredCalendarEvent(db, id: decisionID)
    let source = decision?.occurrenceState == .replacement ? decision! : master
    return CalendarSeriesContext(
      invoked: invoked, master: master, decision: decision, source: source,
      ownership: ownership)
  }

  private static func currentSeriesSegment(
    _ db: Database, eventID: String
  ) throws -> (CalendarEventRow, CalendarSeriesOwnership) {
    guard
      let ownership = try CalendarTimelineQueries.getCalendarSeriesOwnership(
        db, eventId: eventID),
      ownership.isActive,
      let segment = try CalendarTimelineQueries.getStoredCalendarEvent(
        db, id: ownership.segmentEventId)
    else {
      throw LorvexCoreError.notFound(entity: .calendarSeries, id: eventID)
    }
    return (segment, ownership)
  }

  private static func existingUpdateFields(_ row: CalendarEventRow) -> CalendarUpdateExisting {
    CalendarUpdateExisting(
      startDate: row.startDate.asString,
      startTime: row.startTime?.asString,
      endDate: row.endDate?.asString,
      endTime: row.endTime?.asString,
      allDay: row.allDay,
      timezone: row.timezone,
      recurrence: row.recurrence)
  }

  private func upsertOccurrenceDecision(
    _ db: Database,
    hlc: HlcSession,
    deviceId: String,
    context: CalendarSeriesContext,
    occurrenceDate: String,
    state: CalendarOccurrenceState,
    updates: ScopedCalendarEventUpdates? = nil
  ) throws -> CalendarTimelineEvent {
    guard let generation = context.master.recurrenceGeneration else {
      throw LorvexCoreError.unsupportedOperation(
        "Recurring calendar series '\(context.master.id)' has no occurrence generation.")
    }
    let id = CalendarOccurrenceDecisionID.make(
      seriesId: context.master.id,
      recurrenceGeneration: generation,
      recurrenceInstanceDate: occurrenceDate)
    let source = state == .replacement ? context.source : context.master
    let effectiveUpdates = updates ?? ScopedCalendarEventUpdates()
    let sourceIsReplacement = source.seriesId != nil && source.occurrenceState == .replacement
    let timing = Self.resolvedScopedTiming(
      row: source,
      defaultStartDate: sourceIsReplacement ? source.startDate.asString : occurrenceDate,
      updates: effectiveUpdates)
    let title = effectiveUpdates.title ?? source.title
    let timezone =
      try effectiveUpdates.timezone.trimmedNilIfEmpty ?? source.timezone
      ?? WorkflowTimezone.anchoredTimezoneName(db)
    let description = effectiveUpdates.notes ?? source.description
    let location = effectiveUpdates.location ?? source.location
    let url = (effectiveUpdates.url ?? source.url).trimmedNilIfEmpty
    let color = (effectiveUpdates.color ?? source.color).trimmedNilIfEmpty
    let eventType =
      try Self.calendarEventType(
        effectiveUpdates.eventType ?? source.eventType.rawValue) ?? .event
    let personName = (effectiveUpdates.personName ?? source.personName).trimmedNilIfEmpty
    let attendees = try Self.resolvedCreateAttendees(
      db, eventID: source.id, patch: effectiveUpdates.attendees)

    let event: JSONValue
    let before: JSONValue?
    if let existing = context.decision {
      before = try CalendarEventLoad.loadCalendarEventJSON(db, eventId: id)
      guard let before else {
        throw LorvexCoreError.notFound(entity: .calendarEvent, id: id)
      }
      let input: CalendarEventUpdateInput
      if state == .replacement {
        input = CalendarEventUpdateInput(
          id: id,
          title: title,
          recurrence: .unset,
          timezone: Self.replacementPatch(timezone),
          startDate: .set(timing.startDate),
          startTime: Self.replacementPatch(timing.startTime),
          endDate: Self.replacementPatch(timing.endDate),
          endTime: Self.replacementPatch(timing.endTime),
          allDay: timing.allDay,
          description: Self.replacementPatch(description),
          location: Self.replacementPatch(location),
          url: Self.replacementPatch(url),
          color: Self.replacementPatch(color),
          eventType: .set(eventType),
          personName: Self.replacementPatch(personName),
          attendees: attendees.map(Patch.set) ?? .clear,
          occurrenceState: .set(state))
      } else {
        input = CalendarEventUpdateInput(id: id, occurrenceState: .set(state))
      }
      let result = try CalendarEventUpdate.updateCalendarEvent(
        db, hlc: hlc, input: input, before: before,
        beforeRecurrence: nil, existing: Self.existingUpdateFields(existing))
      event = result.event
    } else {
      before = nil
      let input = CalendarEventCreateInput(
        title: title,
        recurrence: nil,
        timezone: timezone,
        startDate: timing.startDate,
        startTime: timing.startTime,
        endDate: timing.endDate,
        endTime: timing.endTime,
        allDay: timing.allDay,
        description: description,
        location: location,
        url: url,
        color: color,
        eventType: eventType,
        personName: personName,
        seriesId: context.master.id,
        recurrenceInstanceDate: occurrenceDate,
        occurrenceState: state,
        recurrenceGeneration: generation,
        attendees: attendees)
      event = try CalendarEventCreate.createCalendarEvent(
        db, hlc: hlc, eventId: id, input: input
      ).event
    }

    try enqueueUpsert(
      db, hlc: hlc, deviceId: deviceId, kind: .calendarEvent, entityId: id)
    try writeChangelogRow(
      db,
      ChangelogEntry(
        operation: "set_occurrence_\(state.rawValue)",
        entityType: EntityName.calendarEvent,
        entityId: id,
        summary: "Set occurrence '\(occurrenceDate)' to \(state.rawValue)",
        before: before,
        after: event),
      deviceId: deviceId)
    return try SwiftLorvexCalendarDeserializers.event(event)
  }

  /// Inline adapter for generic delete paths that discover they were handed a
  /// visible replacement id. Deleting a replacement means cancelling that
  /// occurrence, not tombstoning the decision register.
  func cancelOccurrenceDecisionInline(
    _ db: Database,
    hlc: HlcSession,
    deviceId: String,
    eventID: String,
    occurrenceDate: String
  ) throws -> CalendarTimelineEvent {
    let context = try Self.seriesContext(
      db, eventID: eventID, occurrenceDate: occurrenceDate)
    _ = try upsertOccurrenceDecision(
      db, hlc: hlc, deviceId: deviceId, context: context,
      occurrenceDate: occurrenceDate, state: .cancelled)
    return SwiftLorvexCalendarDeserializers.event(context.master)
  }

  // MARK: - Edit

  func editThisOnlyCalendarEvent(
    eventID: CalendarTimelineEvent.ID,
    occurrenceDate: String,
    updates: ScopedCalendarEventUpdates
  ) throws -> ScopedCalendarEventEditResult {
    guard updates.recurrence == .unset else {
      throw LorvexCoreError.validation(
        field: "recurrence",
        message:
          "A single occurrence cannot change recurrence. Use this_and_following or all_in_series.")
    }
    return try withWrite { db, hlc, deviceId in
      let context = try Self.seriesContext(
        db, eventID: eventID, occurrenceDate: occurrenceDate)
      let original = SwiftLorvexCalendarDeserializers.event(context.master)
      let replacement = try self.upsertOccurrenceDecision(
        db, hlc: hlc, deviceId: deviceId, context: context,
        occurrenceDate: occurrenceDate, state: .replacement, updates: updates)
      return ScopedCalendarEventEditResult(
        seriesID: context.master.id,
        originalEvent: original,
        replacementEvent: replacement)
    }
  }

  func editAllInSeriesCalendarEvent(
    eventID: CalendarTimelineEvent.ID,
    updates: ScopedCalendarEventUpdates
  ) throws -> ScopedCalendarEventEditResult {
    try withWrite { db, hlc, deviceId in
      let (master, _) = try Self.currentSeriesSegment(db, eventID: eventID)
      guard master.recurrence != nil else {
        throw LorvexCoreError.validation(
          field: "event_id", message: "The calendar event is not a recurring series.")
      }
      return try self.editCurrentSeriesSegmentInTx(
        db, hlc: hlc, deviceId: deviceId, master: master, updates: updates)
    }
  }

  private func editCurrentSeriesSegmentInTx(
    _ db: Database,
    hlc: HlcSession,
    deviceId: String,
    master: CalendarEventRow,
    updates: ScopedCalendarEventUpdates
  ) throws -> ScopedCalendarEventEditResult {
    guard let before = try CalendarEventLoad.loadCalendarEventJSON(db, eventId: master.id) else {
      throw LorvexCoreError.notFound(entity: .calendarSeries, id: master.id)
    }
    let input = CalendarEventUpdateInput(
      id: master.id,
      title: updates.title,
      recurrence: try Self.patchRecurrence(updates.recurrence),
      timezone: Self.patchString(updates.timezone),
      startDate: updates.startDate.map(Patch.set) ?? .unset,
      startTime: updates.startTime.map(Patch.set) ?? .unset,
      endDate: updates.endDate.map(Patch.set) ?? .unset,
      endTime: updates.endTime.map(Patch.set) ?? .unset,
      allDay: updates.allDay,
      description: updates.notes.map(Patch.set) ?? .unset,
      location: updates.location.map(Patch.set) ?? .unset,
      url: Self.patchString(updates.url),
      color: Self.patchString(updates.color),
      eventType: try Self.patchEventType(updates.eventType),
      personName: Self.patchString(updates.personName),
      attendees: Self.patchAttendees(updates.attendees),
      resetOccurrenceDecisions: true)
    let result = try CalendarEventUpdate.updateCalendarEvent(
      db, hlc: hlc, input: input, before: before,
      beforeRecurrence: master.recurrence,
      existing: Self.existingUpdateFields(master))
    try enqueueUpsert(
      db, hlc: hlc, deviceId: deviceId, kind: .calendarEvent,
      entityId: result.eventId)
    try writeChangelogRow(
      db,
      ChangelogEntry(
        operation: "update", entityType: EntityName.calendarEvent,
        entityId: result.eventId, summary: result.summary,
        before: result.before, after: result.event),
      deviceId: deviceId)
    let sweep = try sweepSeriesDecisions(
      db, hlc: hlc, deviceId: deviceId, seriesId: master.id, scope: .all)
    return ScopedCalendarEventEditResult(
      seriesID: master.id,
      replacementEvent: try SwiftLorvexCalendarDeserializers.event(result.event),
      invalidatedReplacementEventIDs: sweep.invalidatedReplacementEventIDs)
  }

  func editThisAndFollowingCalendarEvent(
    eventID: CalendarTimelineEvent.ID,
    occurrenceDate: String,
    updates: ScopedCalendarEventUpdates
  ) throws -> ScopedCalendarEventEditResult {
    try withWrite { db, hlc, deviceId in
      let context = try Self.seriesContext(
        db, eventID: eventID, occurrenceDate: occurrenceDate)
      let master = context.master
      // A split at this segment's first occurrence is exactly an all-in-current-
      // segment edit. Reusing the segment avoids a zero-width boundary and also
      // makes recurrence `.clear` a valid one-off segment transition.
      if occurrenceDate == (try Self.segmentFirstOccurrenceDate(
        master: master, ownership: context.ownership)
      ) {
        return try self.editCurrentSeriesSegmentInTx(
          db, hlc: hlc, deviceId: deviceId, master: master, updates: updates)
      }

      let source = context.source
      let replacementAttendees = try Self.resolvedCreateAttendees(
        db, eventID: source.id, patch: updates.attendees)
      let replacementRecurrence = try Self.scopedReplacementRecurrence(
        original: master.recurrence,
        patch: updates.recurrence,
        occurrenceDate: occurrenceDate,
        seriesStartDate: master.startDate.asString)
      let sourceIsReplacement = source.seriesId != nil && source.occurrenceState == .replacement
      let timing = Self.resolvedScopedTiming(
        row: source,
        defaultStartDate: sourceIsReplacement ? source.startDate.asString : occurrenceDate,
        updates: updates)
      let input = CalendarEventCreateInput(
        title: updates.title ?? source.title,
        recurrence: replacementRecurrence,
        timezone: try updates.timezone.trimmedNilIfEmpty ?? source.timezone
          ?? WorkflowTimezone.anchoredTimezoneName(db),
        startDate: timing.startDate,
        startTime: timing.startTime,
        endDate: timing.endDate,
        endTime: timing.endTime,
        allDay: timing.allDay,
        description: updates.notes ?? source.description,
        location: updates.location ?? source.location,
        url: (updates.url ?? source.url).trimmedNilIfEmpty,
        color: (updates.color ?? source.color).trimmedNilIfEmpty,
        eventType: try Self.calendarEventType(
          updates.eventType ?? source.eventType.rawValue),
        personName: (updates.personName ?? source.personName).trimmedNilIfEmpty,
        seriesCutoverId: CalendarSeriesCutoverID.make(
          lineageRootId: context.ownership.lineageRootId,
          cutoverDate: occurrenceDate),
        attendees: replacementAttendees)
      let cutover = try self.upsertCalendarSeriesCutover(
        db, hlc: hlc, deviceId: deviceId,
        lineageRootId: context.ownership.lineageRootId,
        cutoverDate: occurrenceDate,
        state: .active,
        operation: "split_calendar_series")
      guard cutover.state == .active else {
        throw LorvexCoreError.validation(
          field: "occurrence_date",
          message: "This calendar-series boundary was previously deleted and cannot be reused.")
      }
      let sweep = try self.sweepSeriesDecisions(
        db, hlc: hlc, deviceId: deviceId, seriesId: master.id,
        scope: .onOrAfter(occurrenceDate))

      let event: JSONValue
      let before: JSONValue?
      if let existing = try CalendarTimelineQueries.getStoredCalendarEvent(
        db, id: cutover.id)
      {
        guard existing.seriesCutoverId == cutover.id, existing.seriesId == nil,
          let existingJSON = try CalendarEventLoad.loadCalendarEventJSON(
            db, eventId: cutover.id)
        else {
          throw LorvexCoreError.validation(
            field: "event_id",
            message: "The deterministic calendar segment id is already claimed.")
        }
        before = existingJSON
        let update = CalendarEventUpdateInput(
          id: cutover.id,
          title: input.title,
          recurrence: replacementRecurrence.map(Patch.set) ?? .clear,
          timezone: Self.replacementPatch(input.timezone),
          startDate: .set(input.startDate),
          startTime: Self.replacementPatch(input.startTime),
          endDate: Self.replacementPatch(input.endDate),
          endTime: Self.replacementPatch(input.endTime),
          allDay: input.allDay,
          description: Self.replacementPatch(input.description),
          location: Self.replacementPatch(input.location),
          url: Self.replacementPatch(input.url),
          color: Self.replacementPatch(input.color),
          eventType: .set(input.eventType ?? .event),
          personName: Self.replacementPatch(input.personName),
          attendees: replacementAttendees.map(Patch.set) ?? .clear,
          resetOccurrenceDecisions: true)
        let updated = try CalendarEventUpdate.updateCalendarEvent(
          db, hlc: hlc, input: update, before: existingJSON,
          beforeRecurrence: existing.recurrence,
          existing: Self.existingUpdateFields(existing))
        event = updated.event
        _ = try self.sweepSeriesDecisions(
          db, hlc: hlc, deviceId: deviceId, seriesId: cutover.id, scope: .all)
      } else {
        before = nil
        event = try CalendarEventCreate.createCalendarEvent(
          db, hlc: hlc, eventId: cutover.id, input: input).event
      }
      try self.enqueueUpsert(
        db, hlc: hlc, deviceId: deviceId, kind: .calendarEvent,
        entityId: cutover.id)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: SyncNaming.opUpsert,
          entityType: EntityName.calendarEvent,
          entityId: cutover.id,
          summary: "Created calendar-series segment at '\(occurrenceDate)'",
          before: before,
          after: event),
        deviceId: deviceId)
      return ScopedCalendarEventEditResult(
        seriesID: master.id,
        originalEvent: SwiftLorvexCalendarDeserializers.event(master),
        replacementEvent: try SwiftLorvexCalendarDeserializers.event(event),
        invalidatedReplacementEventIDs: sweep.invalidatedReplacementEventIDs)
    }
  }

  // MARK: - Delete

  func deleteThisOnlyCalendarEvent(
    eventID: CalendarTimelineEvent.ID,
    occurrenceDate: String
  ) throws -> ScopedCalendarEventDeleteResult {
    try withWrite { db, hlc, deviceId in
      let context = try Self.seriesContext(
        db, eventID: eventID, occurrenceDate: occurrenceDate)
      let invalidatedReplacementEventIDs =
        context.decision.flatMap { decision in
          decision.occurrenceState == .replacement ? [decision.id] : nil
        } ?? []
      _ = try self.upsertOccurrenceDecision(
        db, hlc: hlc, deviceId: deviceId, context: context,
        occurrenceDate: occurrenceDate, state: .cancelled)
      return ScopedCalendarEventDeleteResult(
        seriesID: context.master.id,
        event: SwiftLorvexCalendarDeserializers.event(context.master),
        invalidatedReplacementEventIDs: invalidatedReplacementEventIDs)
    }
  }

  func restoreThisOnlyCalendarEvent(
    eventID: CalendarTimelineEvent.ID,
    occurrenceDate: String
  ) throws -> CalendarTimelineEvent {
    try withWrite { db, hlc, deviceId in
      let context = try Self.seriesContext(
        db, eventID: eventID, occurrenceDate: occurrenceDate)
      guard let decision = context.decision, decision.occurrenceState != .inherit else {
        return SwiftLorvexCalendarDeserializers.event(context.master)
      }
      _ = try self.upsertOccurrenceDecision(
        db, hlc: hlc, deviceId: deviceId, context: context,
        occurrenceDate: occurrenceDate, state: .inherit)
      return SwiftLorvexCalendarDeserializers.event(context.master)
    }
  }

  func deleteAllInSeriesCalendarEvent(
    eventID: CalendarTimelineEvent.ID
  ) throws -> ScopedCalendarEventDeleteResult {
    try withWrite { db, hlc, deviceId in
      let (master, ownership) = try Self.currentSeriesSegment(db, eventID: eventID)
      return try self.deleteCurrentSeriesSegmentInTx(
        db, hlc: hlc, deviceId: deviceId,
        master: master, ownership: ownership)
    }
  }

  private func deleteCurrentSeriesSegmentInTx(
    _ db: Database,
    hlc: HlcSession,
    deviceId: String,
    master: CalendarEventRow,
    ownership: CalendarSeriesOwnership
  ) throws -> ScopedCalendarEventDeleteResult {
    if let cutoverDate = ownership.lowerBoundCutoverDate {
      let cutover = try upsertCalendarSeriesCutover(
        db, hlc: hlc, deviceId: deviceId,
        lineageRootId: ownership.lineageRootId,
        cutoverDate: cutoverDate,
        state: .deleted,
        operation: "delete_calendar_series_segment")
      guard cutover.id == master.id else {
        throw LorvexCoreError.validation(
          field: "event_id", message: "The calendar segment boundary identity is inconsistent.")
      }
    }
    let sweep = try sweepSeriesDecisions(
      db, hlc: hlc, deviceId: deviceId, seriesId: master.id, scope: .all)
    let deleted = try deleteCalendarEventRowInline(
      db, hlc: hlc, deviceId: deviceId, id: master.id)
    return ScopedCalendarEventDeleteResult(
      seriesID: master.id,
      invalidatedReplacementEventIDs: sweep.invalidatedReplacementEventIDs,
      noop: !deleted && !sweep.deletedAny)
  }

  func deleteThisAndFollowingCalendarEvent(
    eventID: CalendarTimelineEvent.ID,
    occurrenceDate: String
  ) throws -> ScopedCalendarEventDeleteResult {
    let outcome = try withWrite {
      db, hlc, deviceId -> (
        seriesID: String, event: CalendarTimelineEvent?, invalidatedIDs: [String], noop: Bool
      ) in
      let context = try Self.seriesContext(
        db, eventID: eventID, occurrenceDate: occurrenceDate)
      let master = context.master
      if occurrenceDate == (try Self.segmentFirstOccurrenceDate(
        master: master, ownership: context.ownership)
      ) {
        let deleted = try self.deleteCurrentSeriesSegmentInTx(
          db, hlc: hlc, deviceId: deviceId,
          master: master, ownership: context.ownership)
        return (
          deleted.seriesID ?? master.id,
          deleted.event,
          deleted.invalidatedReplacementEventIDs,
          deleted.noop)
      }

      let cutover = try self.upsertCalendarSeriesCutover(
        db, hlc: hlc, deviceId: deviceId,
        lineageRootId: context.ownership.lineageRootId,
        cutoverDate: occurrenceDate,
        state: .deleted,
        operation: "delete_calendar_series_tail")
      let predecessorSweep = try self.sweepSeriesDecisions(
        db, hlc: hlc, deviceId: deviceId, seriesId: master.id,
        scope: .onOrAfter(occurrenceDate))
      let tailSweep = try self.sweepSeriesDecisions(
        db, hlc: hlc, deviceId: deviceId, seriesId: cutover.id, scope: .all)
      _ = try self.deleteCalendarEventRowInline(
        db, hlc: hlc, deviceId: deviceId, id: cutover.id)
      return (
        master.id,
        SwiftLorvexCalendarDeserializers.event(master),
        predecessorSweep.invalidatedReplacementEventIDs
          + tailSweep.invalidatedReplacementEventIDs,
        false)
    }
    return ScopedCalendarEventDeleteResult(
      seriesID: outcome.seriesID, event: outcome.event,
      invalidatedReplacementEventIDs: outcome.invalidatedIDs,
      noop: outcome.noop)
  }
}
