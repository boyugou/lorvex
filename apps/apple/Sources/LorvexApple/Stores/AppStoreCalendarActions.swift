import Foundation
import LorvexCore
import LorvexDomain

extension AppStore {

  func prepareCalendarDraft(for event: CalendarTimelineEvent) {
    draftCalendarTitle = event.title
    draftCalendarTiming = CalendarEventTiming(event: event, fallbackDay: draftCalendarTiming.start)
    draftCalendarLocation = event.location ?? ""
    draftCalendarNotes = event.notes ?? ""
    draftCalendarColor = event.color
    // Parse the canonical recurrence JSON back into the typed rule so the Repeat
    // row opens on the current cadence; nil for a one-off event.
    if let raw = event.recurrenceRule {
      if let rule = TaskRecurrenceRule.bridgeRule(from: raw) {
        draftCalendarRecurrence = rule
        calendarDraftStorage.draftCalendarRecurrenceBaseline = .known(rule)
      } else {
        draftCalendarRecurrence = nil
        calendarDraftStorage.draftCalendarRecurrenceBaseline = .opaque
      }
    } else {
      draftCalendarRecurrence = nil
      calendarDraftStorage.draftCalendarRecurrenceBaseline = .known(nil)
    }
    calendarDraftStorage.draftCalendarRecurrenceWasEdited = false
    // Default to the Lorvex calendar; the edit-open path resolves the mirror's
    // actual calendar asynchronously (`resolveDraftTargetCalendar(for:)`).
    draftCalendarTargetCalendarID = nil
  }

  /// Reset the shared calendar-event draft to fresh defaults before presenting
  /// the create sheet: an untitled one-hour event from the next full hour. The
  /// draft fields are reused by the edit flow (``prepareCalendarDraft(for:)``),
  /// so a create sheet opened after an edit would otherwise inherit the edited
  /// event's title and times. The current draft is stashed first so an open
  /// inline edit is restored when the create sheet dismisses.
  func beginCreateCalendarDraft() {
    stashCalendarDraftForCreate()
    draftCalendarTitle = ""
    draftCalendarTiming = .nextHourBlock(after: Date())
    draftCalendarLocation = ""
    draftCalendarNotes = ""
    draftCalendarColor = nil
    draftCalendarRecurrence = nil
    calendarDraftStorage.draftCalendarRecurrenceWasEdited = false
    calendarDraftStorage.draftCalendarRecurrenceBaseline = .known(nil)
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
          startDate: draftCalendarTiming.startDate,
          endDate: draftCalendarTiming.endDate,
          startTime: draftCalendarTiming.startTime,
          endTime: draftCalendarTiming.endTime,
          allDay: draftCalendarTiming.allDay,
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
    calendarDraftStorage.draftCalendarRecurrenceWasEdited = false
    calendarDraftStorage.draftCalendarRecurrenceBaseline = .known(nil)
    selection = .calendar
  }

  func updateCalendarEvent(_ event: CalendarTimelineEvent) async {
    guard event.editable, !event.supportsScopedMutation else { return }
    await perform {
      let notes = draftCalendarNotes.trimmingCharacters(in: .whitespacesAndNewlines)
      let updated = try await core.updateCalendarEvent(
        id: event.eventID,
        title: draftCalendarTitle.trimmingCharacters(in: .whitespacesAndNewlines),
        startDate: draftCalendarTiming.startDate,
        endDate: draftCalendarTiming.endDate(updating: event.endDate),
        startTime: draftCalendarTiming.startTime,
        endTime: draftCalendarTiming.endTime,
        allDay: draftCalendarTiming.allDay,
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
      calendarDraftStorage.draftCalendarRecurrenceWasEdited = false
      calendarDraftStorage.draftCalendarRecurrenceBaseline = .known(nil)
      selection = .calendar
    }
  }

  /// Reschedules an existing calendar event to a new start instant and
  /// duration. Used by the week-grid drag-to-move / drag-to-resize gestures
  /// so the user can shift events without opening the edit sheet.
  ///
  /// Keeps the event's existing title / location / notes / all-day flag
  /// intact and only changes the temporal axis. Recurring, all-day, and
  /// multi-day events are no-ops — recurring requires choosing whether to edit
  /// this instance vs the series (which only the sheet exposes), all-day
  /// events have no intra-day position to drag, and a multi-day event shows in
  /// the grid as one piece per day, which the gestures cannot move as a whole
  /// (``CalendarTimelineEvent/isMultiDay``; an event that ends at midnight is a
  /// one-day event and does move).
  ///
  /// - Parameters:
  ///   - event: The event being rescheduled.
  ///   - newStart: The new start instant.
  ///   - newEnd: The new end instant. A resize to the bottom of the grid passes
  ///     midnight at the start of the next day (`dateAtMinute`), which is
  ///     stored as that day at 00:00.
  ///   - notes: Optional notes override. When nil, leaves notes unchanged.
  ///   - undoManager: When given, the move registers its inverse so ⌘Z puts the
  ///     event back at its previous times; the undo is itself redoable. Only the
  ///     times are written back, so a title or location edited after the move
  ///     survives the undo.
  func rescheduleCalendarEvent(
    _ event: CalendarTimelineEvent,
    newStart: Date,
    newEnd: Date,
    notes: String? = nil,
    undoManager: UndoManager? = nil
  ) async {
    // Defense in depth: the view-side guard also keeps the gesture from firing.
    guard event.editable, !event.allDay, !event.supportsScopedMutation, !event.isMultiDay
    else { return }
    let timing = CalendarEventTiming(start: newStart, end: newEnd, allDay: false)
    let previous = CalendarEventTiming(event: event, fallbackDay: newStart)
    // Passing `nil` to the core's `updateCalendarEvent(notes:)` keeps the
    // existing notes column UNCHANGED (the core maps nil → `.unset`).
    // Passing `""` would overwrite the column to empty and wipe whatever
    // the user typed in the edit sheet — the drag gesture only changes
    // start/end, so notes must stay alone.
    await perform {
      let updated = try await core.updateCalendarEvent(
        id: event.eventID,
        title: event.title,
        startDate: timing.startDate,
        // An event that had an end date and now fits in one day sends its
        // start date: nil keeps the stored end, which would stretch an event
        // moved up from a midnight end into the next day.
        endDate: timing.endDate(updating: event.endDate),
        startTime: timing.startTime,
        endTime: timing.endTime,
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
      registerEventTimingUndo(
        eventID: event.eventID, undo: previous, redo: timing, undoManager: undoManager)
    }
  }

  /// "Move Event": the name of the Edit menu's undo and redo item for dragging
  /// an event to another time or resizing it.
  static var moveEventTitle: String {
    String(
      localized: "calendar.action.move_event", defaultValue: "Move Event",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// Registers `undo` as the manager's next undo and `redo` as what undoing
  /// re-registers, so ⌘Z and ⇧⌘Z move the event between the two timings. The
  /// handler registers the opposite pair synchronously, while the manager is
  /// still undoing, which is what makes it a redo rather than a new undo; the
  /// write runs afterwards on the main actor.
  private func registerEventTimingUndo(
    eventID: CalendarTimelineEvent.ID, undo: LorvexCore.CalendarEventTiming,
    redo: LorvexCore.CalendarEventTiming,
    undoManager: UndoManager?
  ) {
    guard let undoManager else { return }
    undoManager.registerUndo(withTarget: self) { store in
      MainActor.assumeIsolated {
        store.registerEventTimingUndo(
          eventID: eventID, undo: redo, redo: undo, undoManager: undoManager)
        Task { @MainActor in
          await store.perform { try await store.applyEventTiming(undo, toEventWithID: eventID) }
        }
      }
    }
    undoManager.setActionName(Self.moveEventTitle)
  }

  /// Writes only the start and end of the stored event `id`, leaving its title,
  /// location, and notes as they are now, and mirrors the change to Calendar. An
  /// event that no longer exists is left alone.
  private func applyEventTiming(
    _ timing: LorvexCore.CalendarEventTiming, toEventWithID id: CalendarTimelineEvent.ID
  ) async throws {
    guard let stored = try await core.getCalendarEvent(id: id) else { return }
    let updated = try await core.updateCalendarEvent(
      id: id,
      title: nil,
      startDate: timing.startDate,
      endDate: timing.endDate(updating: stored.endDate),
      startTime: timing.startTime,
      endTime: timing.endTime,
      allDay: nil,
      location: nil,
      notes: nil
    )
    await writeBackToEventKit(
      updated, notesPatch: .preserve, taskID: nil, operation: "eventkit-reschedule",
      target: .keepExisting)
    try await refreshCurrentCalendarTimeline()
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
  /// canonical Lorvex events, which is how they reach the week grid. A caller
  /// whose change added or moved no calendar event (a task mutation) passes
  /// `ingestingEventKit: false` to read the window from the store as it stands,
  /// without fetching EventKit again.
  func refreshCalendarTimeline(
    anchorDate: Date? = nil, dayCount: Int = 14, requestCalendarAccess: Bool = false,
    ingestingEventKit: Bool = true
  ) async throws {
    let from =
      anchorDate.map { Self.ymdFormatter.string(from: $0) } ?? logicalTodayDateString
    let to = LorvexDateFormatters.ymdUTCAddingDays(from, days: dayCount) ?? from
    calendarStorage.timelineLoadToken &+= 1
    let loadToken = calendarStorage.timelineLoadToken
    if ingestingEventKit, let coordinator = eventKitCoordinator,
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
    async let loadedTasks = core.getScheduledTasks(
      from: from, to: to, limit: CalendarGridModel.windowTaskLimit)
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
  /// ~42-day span back down to the day/week default of 14. `ingestingEventKit`
  /// carries through to the load, as ``refreshCalendarTimeline`` takes it.
  func refreshCurrentCalendarTimeline(ingestingEventKit: Bool = true) async throws {
    guard let timeline = calendarTimeline,
      let from = Self.ymdFormatter.date(from: timeline.from)
    else {
      try await refreshCalendarTimeline(ingestingEventKit: ingestingEventKit)
      return
    }
    let dayCount: Int
    if let to = Self.ymdFormatter.date(from: timeline.to) {
      let days = Calendar.current.dateComponents([.day], from: from, to: to).day ?? 14
      dayCount = max(days, 1)
    } else {
      dayCount = 14
    }
    try await refreshCalendarTimeline(
      anchorDate: from, dayCount: dayCount, ingestingEventKit: ingestingEventKit)
  }

  /// Re-loads the calendar window while the Calendar is on screen. A task
  /// change that leaves Today's own list as it was (a task planned for another
  /// day is completed, deferred, or cancelled) would otherwise leave the grid
  /// drawing the task as it was. A task change adds no calendar event, so the
  /// window is read from the store without fetching EventKit again; the EventKit
  /// observer ingests when the app's own write-back changes EventKit. A failed
  /// read keeps what is shown.
  func reloadCalendarTimelineIfShown() async {
    guard selection == .calendar else { return }
    try? await refreshCurrentCalendarTimeline(ingestingEventKit: false)
  }

  /// Ensure today's schedule is loaded and freshly ingested for the Today
  /// surface. Today reads `provider_calendar_events` (the EventKit mirror) both
  /// to display the day's events and — through suggested times — to place
  /// tasks around them, but the mirror is otherwise refreshed only by the Calendar
  /// surface and the EventKit change observer. Without this, opening straight to
  /// Today and suggesting times would place them against a stale or empty
  /// mirror.
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

  /// Exports the calendar timeline window to ICS content. `from` and `to`
  /// are optional ISO-8601 date strings; when `nil`, the current timeline
  /// window is exported. Errors surface through `errorMessage`.
  func exportCalendarICS(from: String?, to: String?) async throws -> String {
    try await core.exportCalendarICS(from: from, to: to)
  }
}
