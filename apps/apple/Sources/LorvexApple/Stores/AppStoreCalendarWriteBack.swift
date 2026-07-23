import Foundation
import LorvexCore
import LorvexDomain

extension AppStore {
  /// Write a Lorvex-originated event into an EventKit calendar via the
  /// coordinator. `target` selects the calendar — the dedicated Lorvex calendar
  /// by default, the user's chosen calendar for form saves, or `.keepExisting`
  /// for temporal-only edits that must not relocate the event. Best-effort:
  /// failures surface in the export report but never fail the canonical core
  /// write.
  @discardableResult
  func writeBackToEventKit(
    _ event: CalendarTimelineEvent, notesPatch: EventKitNotesPatch,
    taskID: String?, operation: String,
    lorvexEventID: String? = nil,
    target: EventKitWriteTarget = .lorvexDefault
  ) async -> Bool {
    let replacementNotes: String?
    switch notesPatch {
    case .preserve: replacementNotes = nil
    case .replace(let notes): replacementNotes = notes
    }
    guard let coordinator = eventKitCoordinator else { return false }
    guard await coordinator.integrationEnabled() else {
      lastCalendarExportReport = .skipped(operation: operation)
      return false
    }
    let resolvedEventID = lorvexEventID ?? event.eventID
    do {
      guard
        let projected = try await core.getCalendarEventForExternalProjection(
          id: resolvedEventID)
      else {
        throw LorvexCoreError.notFound(entity: .calendarEvent, id: resolvedEventID)
      }
      guard let export = CalendarEventExport(event: projected, notes: replacementNotes) else {
        throw LorvexCoreError.unsupportedOperation(
          "Calendar event '\(resolvedEventID)' could not be projected for EventKit")
      }
      _ = try await coordinator.writeBack(
        taskID: taskID,
        existingKey: nil,
        lorvexEventID: resolvedEventID,
        title: export.title,
        start: export.startDate,
        end: export.endDate,
        isAllDay: export.isAllDay,
        location: export.location,
        notesPatch: notesPatch,
        recurrence: export.recurrence,
        target: target)
      lastCalendarExportReport = .succeeded(
        operation: operation, eventCount: 1, eventID: resolvedEventID)
      return true
    } catch {
      lastCalendarExportReport = .failed(operation: operation, error: error)
      return false
    }
  }

  /// Whether an "Add to Calendar" affordance should be offered.
  var canAddTaskToCalendar: Bool { eventKitCoordinator != nil && eventKitIntegrationEnabled }

  /// Whether `task` is schedulable into Calendar without inventing a date.
  func canAddTaskToCalendar(_ task: LorvexTask) -> Bool {
    canAddTaskToCalendar && task.plannedDate != nil
  }

  /// Schedule a task into the dedicated Lorvex calendar and bind the resulting
  /// EKEvent to the task via `task_provider_event_links`.
  func addTaskToCalendar(_ task: LorvexTask) async {
    guard let coordinator = eventKitCoordinator else { return }
    guard await coordinator.integrationEnabled() else {
      lastCalendarExportReport = .skipped(operation: "eventkit-export")
      return
    }
    guard let day = task.plannedDate else {
      lastCalendarExportReport = .skipped(operation: "eventkit-export")
      errorMessage = String(
        localized: "task_detail.actions.add_to_calendar.no_date_error",
        defaultValue: "Add a planned date before adding this task to Calendar.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
      return
    }
    do {
      if try await coordinator.eventKey(forTask: task.id) != nil {
        lastCalendarExportReport = .skipped(operation: "eventkit-export")
        return
      }
    } catch {
      lastCalendarExportReport = .failed(operation: "eventkit-export", error: error)
      await presentUserFacingError(error)
      return
    }
    let startHour =
      Calendar.current.date(
        bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    let minutes = max(15, task.estimatedMinutes ?? 60)
    let end = startHour.addingTimeInterval(TimeInterval(minutes * 60))
    await perform {
      let event = try await core.createCalendarEvent(
        title: task.title,
        startDate: Self.ymdFormatter.string(from: startHour),
        endDate: nil,
        startTime: Self.hmFormatter.string(from: startHour),
        endTime: Self.hmFormatter.string(from: end),
        allDay: false,
        location: nil,
        notes: nil)
      await writeBackToEventKit(
        event, notesPatch: .replace(nil), taskID: task.id, operation: "eventkit-export")
      try await refreshCurrentCalendarTimeline()
    }
  }
}
