import Foundation
import LorvexCore

extension AppStore {
  /// Save the edit-sheet draft to a recurring calendar event with an explicit
  /// occurrence scope. Every scope routes through the same core workflow so the
  /// app and MCP surfaces cannot disagree about series-reset semantics.
  func saveScopedCalendarEvent(_ event: CalendarTimelineEvent, scope: CalendarEventEditScope) async
  {
    guard event.editable, event.supportsScopedMutation else { return }
    await perform {
      guard let occurrenceDate = event.occurrenceDate else {
        throw LorvexCoreError.validation(
          field: "occurrence_date",
          message: "Recurring calendar occurrence is missing its identity.")
      }
      let notes = draftCalendarNotes.trimmingCharacters(in: .whitespacesAndNewlines)
      let updates = ScopedCalendarEventUpdates(
        title: draftCalendarTitle.trimmingCharacters(in: .whitespacesAndNewlines),
        startDate: Self.ymdFormatter.string(from: draftCalendarDate),
        startTime: draftCalendarAllDay
          ? nil : Self.hmFormatter.string(from: draftCalendarStartTime),
        endTime: draftCalendarAllDay ? nil : Self.hmFormatter.string(from: draftCalendarEndTime),
        allDay: draftCalendarAllDay,
        location: draftCalendarLocation.trimmingCharacters(in: .whitespacesAndNewlines),
        notes: notes,
        recurrence: draftCalendarRecurrencePatch,
        color: draftCalendarColor ?? ""
      )
      let result = try await core.editScopedCalendarEvent(
        eventID: event.eventID,
        occurrenceDate: occurrenceDate,
        scope: scope.rawValue,
        updates: updates
      )
      await mirrorScopedEditToEventKit(
        result, scope: scope, eventID: event.eventID,
        occurrenceDate: event.scopedOccurrenceStartDate,
        notes: notes.trimmedNilIfEmpty)
      try await refreshCurrentCalendarTimeline()
      draftCalendarTitle = ""
      draftCalendarLocation = ""
      draftCalendarNotes = ""
      draftCalendarColor = nil
      draftCalendarRecurrence = nil
      calendarStorage.draftCalendarRecurrenceWasEdited = false
      calendarStorage.draftCalendarRecurrenceBaseline = .known(nil)
      selection = .calendar
    }
  }

  /// Delete a recurring calendar event with an explicit occurrence scope.
  /// `allEvents` removes the currently addressed series segment; `thisEvent`
  /// records a cancellation decision for the tapped occurrence;
  /// `thisAndFollowing` removes that segment from the selected day onward.
  func deleteScopedCalendarEvent(_ event: CalendarTimelineEvent, scope: CalendarEventEditScope)
    async
  {
    guard event.editable, event.supportsScopedMutation else { return }
    await perform {
      guard let occurrenceDate = event.occurrenceDate else {
        throw LorvexCoreError.validation(
          field: "occurrence_date",
          message: "Recurring calendar occurrence is missing its identity.")
      }
      let result = try await core.deleteScopedCalendarEvent(
        eventID: event.eventID,
        occurrenceDate: occurrenceDate,
        scope: scope.rawValue
      )
      await mirrorScopedDeleteToEventKit(
        result, scope: scope, eventID: event.eventID,
        occurrenceDate: event.scopedOccurrenceStartDate)
      try await refreshCurrentCalendarTimeline()
    }
  }

  /// Best-effort EventKit mirror for a scoped edit. The canonical store is
  /// authoritative; this only keeps its EventKit mirror in step. `thisEvent`
  /// writes the one-off before removing the original occurrence.
  /// `thisAndFollowing` uses EventKit's native `.futureEvents` save so the split
  /// cannot leave both an untruncated original and a replacement series.
  private func mirrorScopedEditToEventKit(
    _ result: ScopedCalendarEventEditResult,
    scope: CalendarEventEditScope,
    eventID: String,
    occurrenceDate: Date?,
    notes: String?
  ) async {
    guard eventKitCoordinator != nil, !result.noop,
      let replacement = result.replacementEvent
    else { return }
    let seriesID = result.seriesID ?? eventID
    if scope == .thisAndFollowing {
      guard let coordinator = eventKitCoordinator,
        let occurrenceDate
      else { return }
      guard await coordinator.integrationEnabled() else {
        lastCalendarExportReport = .skipped(operation: "eventkit-scope-edit")
        return
      }
      do {
        guard
          let projected = try await core.getCalendarEventForExternalProjection(
            id: replacement.id)
        else {
          throw LorvexCoreError.notFound(entity: .calendarEvent, id: replacement.id)
        }
        guard let export = CalendarEventExport(event: projected, notes: notes) else {
          throw LorvexCoreError.unsupportedOperation(
            "Calendar event '\(replacement.id)' could not be projected for EventKit")
        }
        _ = try await coordinator.replaceFutureWriteBack(
          originalLorvexEventID: seriesID,
          occurrenceDate: occurrenceDate,
          replacement: export,
          replacementLorvexEventID: replacement.id,
          target: draftEventKitWriteTarget)
        lastCalendarExportReport = .succeeded(
          operation: "eventkit-scope-edit", eventCount: 1, eventID: replacement.id)
      } catch {
        lastCalendarExportReport = .failed(operation: "eventkit-scope-edit", error: error)
        return
      }
      await removeInvalidatedReplacementMirrors(
        result.invalidatedReplacementEventIDs, coordinator: coordinator)
      return
    }

    // Never remove the old EventKit occurrence/series unless its replacement
    // was written successfully. The Lorvex database remains authoritative, but
    // a failed best-effort mirror must not turn a visible old event into data
    // loss inside Calendar or overwrite the failure report with false success.
    guard
      await writeBackToEventKit(
        replacement, notesPatch: .replace(notes), taskID: nil,
        operation: "eventkit-scope-edit",
        lorvexEventID: replacement.id,
        target: draftEventKitWriteTarget)
    else { return }
    if scope == .thisEvent {
      await removeScopedOccurrenceFromEventKit(eventID: seriesID, occurrenceDate: occurrenceDate)
    }
    if let coordinator = eventKitCoordinator {
      await removeInvalidatedReplacementMirrors(
        result.invalidatedReplacementEventIDs, coordinator: coordinator)
    }
  }

  /// Best-effort EventKit mirror for a scoped delete. `thisAndFollowing` uses
  /// EventKit's native future-occurrence span; Lorvex keeps its own durable
  /// cutover and never mirrors provider-derived recurrence truncation back.
  private func mirrorScopedDeleteToEventKit(
    _ result: ScopedCalendarEventDeleteResult,
    scope: CalendarEventEditScope,
    eventID: String,
    occurrenceDate: Date?
  ) async {
    guard !result.noop, let coordinator = eventKitCoordinator else { return }
    guard await coordinator.integrationEnabled() else {
      lastCalendarExportReport = .skipped(operation: "eventkit-scope-delete")
      return
    }
    let seriesID = result.seriesID ?? eventID
    if scope == .thisEvent {
      await removeScopedOccurrenceFromEventKit(eventID: seriesID, occurrenceDate: occurrenceDate)
      await removeInvalidatedReplacementMirrors(
        result.invalidatedReplacementEventIDs, coordinator: coordinator)
      return
    }
    if scope == .allEvents {
      do {
        try await coordinator.removeWriteBack(taskID: nil, lorvexEventID: seriesID)
        lastCalendarExportReport = .succeeded(operation: "eventkit-scope-delete", eventCount: 1)
      } catch {
        lastCalendarExportReport = .failed(operation: "eventkit-scope-delete", error: error)
        return
      }
      await removeInvalidatedReplacementMirrors(
        result.invalidatedReplacementEventIDs, coordinator: coordinator)
      return
    }
    guard let occurrenceDate else { return }
    do {
      try await coordinator.removeFutureWriteBack(
        lorvexEventID: seriesID, occurrenceDate: occurrenceDate)
      lastCalendarExportReport = .succeeded(
        operation: "eventkit-scope-delete", eventCount: 1, eventID: seriesID)
    } catch {
      lastCalendarExportReport = .failed(operation: "eventkit-scope-delete", error: error)
      return
    }
    await removeInvalidatedReplacementMirrors(
      result.invalidatedReplacementEventIDs, coordinator: coordinator)
  }

  private func removeInvalidatedReplacementMirrors(
    _ ids: [String], coordinator: EventKitCoordinator
  ) async {
    for id in Set(ids).sorted() {
      do {
        try await coordinator.removeWriteBack(taskID: nil, lorvexEventID: id)
      } catch {
        lastCalendarExportReport = .failed(
          operation: "eventkit-scope-replacement-delete", error: error)
      }
    }
  }

  private func removeScopedOccurrenceFromEventKit(eventID: String, occurrenceDate: Date?) async {
    guard let coordinator = eventKitCoordinator, let occurrenceDate else { return }
    do {
      try await coordinator.removeOccurrenceWriteBack(
        lorvexEventID: eventID, occurrenceDate: occurrenceDate)
      lastCalendarExportReport = .succeeded(
        operation: "eventkit-scope-occurrence-delete", eventCount: 1, eventID: eventID)
    } catch {
      lastCalendarExportReport = .failed(
        operation: "eventkit-scope-occurrence-delete", error: error)
    }
  }
}

extension CalendarTimelineEvent {
  fileprivate var scopedOccurrenceStartDate: Date? {
    var occurrence = self
    occurrence.startDate = occurrenceDate ?? startDate
    return CalendarEventExport(event: occurrence, notes: nil)?.startDate
  }
}
