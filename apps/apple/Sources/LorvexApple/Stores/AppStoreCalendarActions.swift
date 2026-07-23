import Foundation
import LorvexCore
import LorvexDomain

extension AppStore {

  func prepareCalendarDraft(for event: CalendarTimelineEvent) {
    draftCalendarTitle = event.title
    draftCalendarDate = Self.ymdFormatter.date(from: event.startDate) ?? draftCalendarDate
    // Capture this event's parsed start once and fall back to it explicitly for
    // the end, rather than reading the just-assigned `draftCalendarStartTime`
    // store property (correct only by assignment order).
    let parsedStart =
      event.startTime.flatMap(Self.hmFormatter.date(from:)) ?? draftCalendarStartTime
    draftCalendarStartTime = parsedStart
    draftCalendarEndTime = event.endTime.flatMap(Self.hmFormatter.date(from:)) ?? parsedStart
    draftCalendarAllDay = event.allDay
    draftCalendarLocation = event.location ?? ""
    draftCalendarNotes = event.notes ?? ""
    draftCalendarColor = event.color
    // Parse the canonical recurrence JSON back into the typed rule so the Repeat
    // row opens on the current cadence; nil for a one-off event.
    if let raw = event.recurrenceRule {
      if let rule = TaskRecurrenceRule.bridgeRule(from: raw) {
        draftCalendarRecurrence = rule
        calendarStorage.draftCalendarRecurrenceBaseline = .known(rule)
      } else {
        draftCalendarRecurrence = nil
        calendarStorage.draftCalendarRecurrenceBaseline = .opaque
      }
    } else {
      draftCalendarRecurrence = nil
      calendarStorage.draftCalendarRecurrenceBaseline = .known(nil)
    }
    calendarStorage.draftCalendarRecurrenceWasEdited = false
    // Default to the Lorvex calendar; the edit-open path resolves the mirror's
    // actual calendar asynchronously (`resolveDraftTargetCalendar(for:)`).
    draftCalendarTargetCalendarID = nil
  }

  /// Reset the shared calendar-event draft to fresh defaults before presenting
  /// the create sheet. The draft fields are reused by the edit flow
  /// (``prepareCalendarDraft(for:)``), so a create sheet opened after an edit
  /// would otherwise inherit the edited event's title, date, and times. The
  /// current draft is stashed first so an open inline edit is restored when the
  /// create sheet dismisses.
  func beginCreateCalendarDraft() {
    stashCalendarDraftForCreate()
    let now = Date()
    draftCalendarTitle = ""
    draftCalendarDate = now
    draftCalendarStartTime = now
    draftCalendarEndTime = now.addingTimeInterval(60 * 60)
    draftCalendarAllDay = false
    draftCalendarLocation = ""
    draftCalendarNotes = ""
    draftCalendarColor = nil
    draftCalendarRecurrence = nil
    calendarStorage.draftCalendarRecurrenceWasEdited = false
    calendarStorage.draftCalendarRecurrenceBaseline = .known(nil)
    draftCalendarTargetCalendarID = nil
  }

  func createDraftCalendarEvent() async {
    guard !isCreating else { return }
    isCreating = true
    defer { isCreating = false }
    let notes = draftCalendarNotes.trimmedNilIfEmpty
    guard
      let event = await performCanonicalMutation({
        try await core.createCalendarEvent(
          title: draftCalendarTitle,
          startDate: Self.ymdFormatter.string(from: draftCalendarDate),
          endDate: nil,
          startTime: draftCalendarAllDay
            ? nil : Self.hmFormatter.string(from: draftCalendarStartTime),
          endTime: draftCalendarAllDay ? nil : Self.hmFormatter.string(from: draftCalendarEndTime),
          allDay: draftCalendarAllDay,
          location: draftCalendarLocation.trimmedNilIfEmpty,
          notes: notes,
          recurrence: draftCalendarRecurrence,
          timezone: nil,
          url: nil,
          color: draftCalendarColor,
          eventType: nil,
          personName: nil,
          attendees: nil
        )
      })
    else { return }

    await writeBackToEventKit(
      event, notesPatch: .replace(notes), taskID: nil, operation: "eventkit-export",
      target: draftEventKitWriteTarget)
    await reconcileAfterCommittedMutation(source: "macos.calendar.create.reconcile") {
      try await refreshCurrentCalendarTimeline()
    }
    if calendarTimeline?.events.contains(where: { $0.eventID == event.eventID }) != true {
      calendarTimeline?.events.append(event)
    }
    draftCalendarTitle = ""
    draftCalendarLocation = ""
    draftCalendarNotes = ""
    draftCalendarColor = nil
    draftCalendarRecurrence = nil
    calendarStorage.draftCalendarRecurrenceWasEdited = false
    calendarStorage.draftCalendarRecurrenceBaseline = .known(nil)
    selection = .calendar
  }

  func updateCalendarEvent(_ event: CalendarTimelineEvent) async {
    guard event.editable, !event.supportsScopedMutation else { return }
    await perform {
      let notes = draftCalendarNotes.trimmingCharacters(in: .whitespacesAndNewlines)
      let updated = try await core.updateCalendarEvent(
        id: event.eventID,
        title: draftCalendarTitle.trimmingCharacters(in: .whitespacesAndNewlines),
        startDate: Self.ymdFormatter.string(from: draftCalendarDate),
        endDate: nil,
        startTime: draftCalendarAllDay
          ? nil : Self.hmFormatter.string(from: draftCalendarStartTime),
        endTime: draftCalendarAllDay ? nil : Self.hmFormatter.string(from: draftCalendarEndTime),
        allDay: draftCalendarAllDay,
        // This is a full-object edit surface. Empty values are deliberate
        // clears; nil would mean "leave unchanged" at the core patch boundary.
        location: draftCalendarLocation.trimmingCharacters(in: .whitespacesAndNewlines),
        notes: notes,
        recurrence: draftCalendarRecurrencePatch,
        timezone: nil,
        url: nil,
        color: draftCalendarColor ?? "",
        eventType: nil,
        personName: nil,
        attendees: .unset
      )
      await writeBackToEventKit(
        updated, notesPatch: .replace(notes.trimmedNilIfEmpty), taskID: nil,
        operation: "eventkit-update",
        target: draftEventKitWriteTarget)
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

  /// Reschedules an existing calendar event to a new start instant and
  /// duration. Used by the week-grid drag-to-move / drag-to-resize gestures
  /// so the user can shift events without opening the edit sheet.
  ///
  /// Keeps the event's existing title / location / notes / all-day flag
  /// intact and only changes the temporal axis. Recurring + all-day events
  /// are no-ops — recurring requires choosing whether to edit this instance
  /// vs the series (which only the sheet exposes), and all-day events have
  /// no intra-day position to drag.
  ///
  /// - Parameters:
  ///   - event: The event being rescheduled.
  ///   - newStart: The new start instant. The date portion sets `startDate`
  ///     and the time-of-day portion sets `startTime`.
  ///   - newEnd: The new end instant. Time-of-day portion sets `endTime`;
  ///     the date portion is dropped (events crossing midnight via drag are
  ///     out of scope and the caller is expected to clamp).
  ///   - notes: Optional notes override. When nil, leaves notes unchanged.
  func rescheduleCalendarEvent(
    _ event: CalendarTimelineEvent,
    newStart: Date,
    newEnd: Date,
    notes: String? = nil
  ) async {
    // Multi-day events (event.endDate != event.startDate) appear as per-day
    // clips in the week grid; the drag-gesture math operates on the clip,
    // not the event. Skipping at the store layer is defense in depth — the
    // view-side guard also blocks the gesture from firing.
    let isMultiDay = event.endDate != nil && event.endDate != event.startDate
    guard event.editable, !event.allDay, !event.supportsScopedMutation, !isMultiDay else { return }
    // Passing `nil` to the core's `updateCalendarEvent(notes:)` keeps the
    // existing notes column UNCHANGED (the core maps nil → `.unset`).
    // Passing `""` would overwrite the column to empty and wipe whatever
    // the user typed in the edit sheet — the drag gesture only changes
    // start/end, so notes must stay alone.
    await perform {
      // A bottom-edge resize to 24:00 lands `newEnd` at next-day midnight (see
      // `dateAtMinute`). Persist that as a real end date so the event spans
      // 23:00→00:00 across the boundary instead of collapsing into a same-day
      // negative span that the grid then clamps to a stub.
      let endDate =
        Calendar.current.isDate(newEnd, inSameDayAs: newStart)
        ? nil : Self.ymdFormatter.string(from: newEnd)
      let updated = try await core.updateCalendarEvent(
        id: event.eventID,
        title: event.title,
        startDate: Self.ymdFormatter.string(from: newStart),
        endDate: endDate,
        startTime: Self.hmFormatter.string(from: newStart),
        endTime: Self.hmFormatter.string(from: newEnd),
        allDay: event.allDay,
        location: event.location,
        notes: notes
      )
      // A temporal-only drag must not clear notes already edited in Calendar;
      // an explicit override still distinguishes clear from replacement.
      let notesPatch: EventKitNotesPatch = notes.map { .replace($0.trimmedNilIfEmpty) } ?? .preserve
      await writeBackToEventKit(
        updated, notesPatch: notesPatch, taskID: nil, operation: "eventkit-reschedule",
        target: .keepExisting)
      try await refreshCurrentCalendarTimeline()
    }
  }

  func deleteCalendarEvent(_ event: CalendarTimelineEvent) async {
    guard event.editable, !event.supportsScopedMutation else { return }
    await perform {
      try await core.deleteCalendarEvent(id: event.eventID)
      if let coordinator = eventKitCoordinator {
        do {
          if await coordinator.integrationEnabled() {
            try await coordinator.removeWriteBack(taskID: nil, lorvexEventID: event.eventID)
            lastCalendarExportReport = .succeeded(operation: "eventkit-delete", eventCount: 1)
          } else {
            lastCalendarExportReport = .skipped(operation: "eventkit-delete")
          }
        } catch {
          lastCalendarExportReport = .failed(operation: "eventkit-delete", error: error)
        }
      }
      try await refreshCurrentCalendarTimeline()
    }
  }

  /// Loads a `dayCount`-day calendar timeline window starting at `anchorDate`
  /// (today when `nil`). The day/week surfaces use the default 14-day window;
  /// the month grid passes its exact visible grid span (up to 42 days) so a
  /// busy month's leading/trailing weeks load too.
  ///
  /// EventKit provider events are NOT merged in memory here: the coordinator
  /// ingests them into `provider_calendar_events` (tier-redacted at ingest), and
  /// `loadCalendarTimeline`'s SQL union surfaces them in the same snapshot as
  /// canonical Lorvex events, which is how they reach the week grid.
  func refreshCalendarTimeline(
    anchorDate: Date? = nil, dayCount: Int = 14, requestCalendarAccess: Bool = false
  ) async throws {
    let from =
      anchorDate.map { Self.ymdFormatter.string(from: $0) } ?? logicalTodayDateString
    let to = LorvexDateFormatters.ymdUTCAddingDays(from, days: dayCount) ?? from
    calendarStorage.timelineLoadToken &+= 1
    let loadToken = calendarStorage.timelineLoadToken
    if let coordinator = eventKitCoordinator,
      let instantRange = PlannedDayBridge.instantRange(
        fromLogicalDay: from,
        throughLogicalDay: to,
        timezoneName: logicalTimezoneName)
    {
      do {
        let report = try await coordinator.ingest(
          from: instantRange.start,
          to: instantRange.endExclusive,
          windowStart: from,
          windowEnd: to,
          requestAccess: requestCalendarAccess)
        lastImportedCalendarEventCount = report.ingestedCount
        lastCalendarImportReport = .succeeded(
          operation: "eventkit-import", eventCount: report.ingestedCount)
      } catch {
        lastImportedCalendarEventCount = 0
        lastCalendarImportReport = .failed(operation: "eventkit-import", error: error)
      }
    }
    async let loadedTimeline = core.loadCalendarTimeline(from: from, to: to)
    async let loadedTasks = core.getScheduledTasks(from: from, to: to, limit: 500)
    let timeline = try await loadedTimeline
    let tasks = try await loadedTasks
    // A newer load (week navigation, the EventKit observer, or the view's
    // today-change refetch) superseded this window while these queries were in
    // flight; committing now would pair this window's events with the newer
    // window's scheduled tasks, so discard the stale result.
    guard loadToken == calendarStorage.timelineLoadToken else { return }
    calendarTimeline = timeline
    calendarScheduledTasks = tasks
  }

  /// Re-loads whatever window is currently on screen (day, week, or month) at
  /// its own span, so a mutation-triggered refresh (create/edit/delete/drag)
  /// can't silently shrink a wider window — e.g. narrowing the month grid's
  /// ~42-day span back down to the day/week default of 14.
  func refreshCurrentCalendarTimeline() async throws {
    guard let timeline = calendarTimeline,
      let from = Self.ymdFormatter.date(from: timeline.from)
    else {
      try await refreshCalendarTimeline()
      return
    }
    let dayCount: Int
    if let to = Self.ymdFormatter.date(from: timeline.to) {
      let days = Calendar.current.dateComponents([.day], from: from, to: to).day ?? 14
      dayCount = max(days, 1)
    } else {
      dayCount = 14
    }
    try await refreshCalendarTimeline(anchorDate: from, dayCount: dayCount)
  }

  /// Ensure today's schedule is loaded and freshly ingested for the Today
  /// surface. Today reads `provider_calendar_events` (the EventKit mirror) both
  /// to display the day's events and — through the focus scheduler — to plan
  /// around them, but the mirror is otherwise refreshed only by the Calendar
  /// surface and the EventKit change observer. Without this, opening straight to
  /// Today and auto-scheduling would plan against a stale or empty mirror.
  ///
  /// When the loaded window already spans today (the common case — both Today
  /// and Calendar default to a today-anchored window) the current window is
  /// re-ingested and reloaded, preserving any window the Calendar surface
  /// navigated to. Otherwise a today-anchored window is loaded. Best-effort:
  /// errors (no integration, denied access) are swallowed so Today still renders
  /// its tasks. Never prompts for calendar access (`requestCalendarAccess`
  /// stays false); permission is requested only from the explicit opt-in.
  func loadTodaySchedule() async {
    let today = logicalTodayDateString
    if let timeline = calendarTimeline, timeline.from <= today, today <= timeline.to {
      try? await refreshCurrentCalendarTimeline()
    } else {
      try? await refreshCalendarTimeline()
    }
  }

  /// Plan or re-plan a task onto `day` — the calendar's drag-to-reschedule
  /// write-back. Works for already-scheduled tasks (move in the calendar) and
  /// for unscheduled tasks dragged from Today/Tasks onto the all-day strip
  /// (where `calendarScheduledTasks` doesn't carry them). Preserves every
  /// other field and reloads the surfaces that place the task on a day.
  func rescheduleScheduledTask(id: LorvexTask.ID, to day: Date) async {
    let task = calendarScheduledTasks?.first(where: { $0.id == id })
    await perform {
      let resolved: LorvexTask
      if let task {
        resolved = task
      } else {
        resolved = try await core.loadTask(id: id)
      }
      _ = try await core.updateTask(
        id: resolved.id, title: resolved.title, notes: resolved.notes,
        priority: resolved.priority, estimatedMinutes: resolved.estimatedMinutes,
        dueDate: resolved.dueDate,
        plannedDate: PlannedDayBridge.storageDate(forLocalInstant: day),
        availableFrom: resolved.availableFrom,
        tags: resolved.tags, dependsOn: resolved.dependsOn)
      try await refreshCurrentCalendarTimeline()
      today = try await core.loadToday()
      await republishSurfacesAfterLocalMutation()
    }
  }

  /// Exports the calendar timeline window to ICS content. `from` and `to`
  /// are optional ISO-8601 date strings; when `nil`, the current timeline
  /// window is exported. Errors surface through `errorMessage`.
  func exportCalendarICS(from: String?, to: String?) async throws -> String {
    try await core.exportCalendarICS(from: from, to: to)
  }
}
