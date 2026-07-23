import Foundation
import LorvexCore

extension MobileStore {
  public var canCreateCalendarDraft: Bool {
    calendarDraft.canSubmit && !isMutatingCalendarEvent
  }

  @discardableResult
  public func createDraftCalendarEvent() async -> Bool {
    guard canCreateCalendarDraft else { return false }
    isMutatingCalendarEvent = true
    defer { isMutatingCalendarEvent = false }
    guard
      let event = await performCanonicalMutation({
        try await core.createCalendarEvent(
          title: calendarDraft.trimmedTitle,
          startDate: Self.ymdFormatter.string(from: calendarDraft.date),
          endDate: nil,
          startTime: calendarDraft.allDay
            ? nil : Self.hmFormatter.string(from: calendarDraft.startTime),
          endTime: calendarDraft.allDay
            ? nil : Self.hmFormatter.string(from: calendarDraft.endTime),
          allDay: calendarDraft.allDay,
          location: calendarDraft.trimmedLocation.trimmedNilIfEmpty,
          notes: calendarDraft.trimmedNotes.trimmedNilIfEmpty
        )
      })
    else { return false }

    calendarDraft = MobileCalendarDraft(now: now)
    await reconcileAfterCommittedMutation(source: "ios.calendar.create.reconcile") {
      let date = logicalTodayString
      calendarTimeline = try await core.loadCalendarTimeline(
        from: date,
        to: Self.calendarEndDateString(from: date)
      )
      if calendarTimeline?.events.contains(where: { $0.eventID == event.eventID }) != true {
        calendarTimeline?.events.append(event)
      }
    }
    if calendarTimeline?.events.contains(where: { $0.eventID == event.eventID }) != true {
      calendarTimeline?.events.append(event)
    }
    return true
  }

  public var canUpdateCalendarDraft: Bool {
    calendarDraft.canSubmit && !isMutatingCalendarEvent
  }

  public func prepareCalendarDraft(for event: CalendarTimelineEvent) {
    calendarDraft = MobileCalendarDraft(event: event, fallbackDate: now())
  }

  /// Seed a fresh default draft before presenting the create-event sheet from a
  /// generic "New Event" affordance: a timed one-hour block starting now, to
  /// match the macOS toolbar default and the day-grid tap. `calendarDraft` is
  /// reused by the edit flow (``prepareCalendarDraft(for:)``) and by day-grid
  /// taps, so a create sheet opened from the toolbar would otherwise inherit
  /// the last edited or tapped-slot draft. Day-grid taps seed their own time
  /// slot and bypass this.
  public func beginCreateCalendarDraft() {
    let start = now()
    calendarDraft = MobileCalendarDraft(
      date: start,
      startTime: start,
      endTime: start.addingTimeInterval(60 * 60),
      allDay: false
    )
  }

  @discardableResult
  public func updateCalendarEvent(_ event: CalendarTimelineEvent) async -> Bool {
    guard event.editable, !event.supportsScopedMutation, canUpdateCalendarDraft else {
      return false
    }
    isMutatingCalendarEvent = true
    defer { isMutatingCalendarEvent = false }
    do {
      let updated = try await core.updateCalendarEvent(
        id: event.eventID,
        title: calendarDraft.trimmedTitle,
        startDate: Self.ymdFormatter.string(from: calendarDraft.date),
        endDate: nil,
        startTime: calendarDraft.allDay
          ? nil : Self.hmFormatter.string(from: calendarDraft.startTime),
        endTime: calendarDraft.allDay ? nil : Self.hmFormatter.string(from: calendarDraft.endTime),
        allDay: calendarDraft.allDay,
        // The edit form is a full-object editor: pass the trimmed values directly
        // (not `trimmedNilIfEmpty`) so clearing the field actually clears it. With
        // `trimmedNilIfEmpty`, an emptied field became nil → `.unset` → no change, so
        // the old value reappeared on reload. Empty stores as "" rather than NULL.
        location: calendarDraft.trimmedLocation,
        notes: calendarDraft.trimmedNotes
      )
      if let index = calendarTimeline?.events.firstIndex(where: { $0.id == updated.id }) {
        calendarTimeline?.events[index] = updated
      }
      calendarDraft = MobileCalendarDraft(now: now)
      errorMessage = nil
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  /// Reschedules an existing calendar event to a new start instant + end
  /// instant. Used by the iPhone day-view drag-to-reschedule gesture (long-
  /// press then drag) so the user can shift an event without opening the
  /// edit sheet. Keeps title / location / notes / all-day flag intact;
  /// recurring + non-editable events are silently skipped.
  @discardableResult
  public func rescheduleCalendarEvent(
    _ event: CalendarTimelineEvent,
    newStart: Date,
    newEnd: Date
  ) async -> Bool {
    // Same multi-day guard as the macOS path. The iPhone duration calculation
    // is also brittle when the event crosses midnight (start 23:00 / end
    // 01:00 yields a negative `(end - start)` in same-day minutes), so this
    // check is doubly load-bearing here.
    let isMultiDay = event.endDate != nil && event.endDate != event.startDate
    guard event.editable, !event.allDay, !event.supportsScopedMutation,
      !isMultiDay, !isMutatingCalendarEvent
    else { return false }
    isMutatingCalendarEvent = true
    defer { isMutatingCalendarEvent = false }
    do {
      let updated = try await core.updateCalendarEvent(
        id: event.eventID,
        title: event.title,
        startDate: Self.ymdFormatter.string(from: newStart),
        endDate: nil,
        startTime: Self.hmFormatter.string(from: newStart),
        endTime: Self.hmFormatter.string(from: newEnd),
        allDay: event.allDay,
        location: event.location,
        notes: nil
      )
      if let index = calendarTimeline?.events.firstIndex(where: { $0.id == updated.id }) {
        calendarTimeline?.events[index] = updated
      }
      errorMessage = nil
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  @discardableResult
  public func deleteCalendarEvent(_ event: CalendarTimelineEvent) async -> Bool {
    guard event.editable, !event.supportsScopedMutation, !isMutatingCalendarEvent else {
      return false
    }
    isMutatingCalendarEvent = true
    defer { isMutatingCalendarEvent = false }
    do {
      try await core.deleteCalendarEvent(id: event.eventID)
      calendarTimeline?.events.removeAll { $0.id == event.id }
      errorMessage = nil
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  /// Loads the calendar timeline window around `anchor` for the day/3-day
  /// view. Fetches `[anchor-7d, anchor+7d]` so horizontal swipes in either
  /// direction render without an immediate refetch; the day view re-invokes
  /// this when the visible date nears the window edge. Reuses the existing
  /// `loadCalendarTimeline` core read — no new data path.
  func refreshCalendarTimeline(around anchor: Date) async {
    let anchorDay = Self.ymdFormatter.string(from: anchor)
    let start = LorvexDateFormatters.ymdUTCAddingDays(anchorDay, days: -7) ?? anchorDay
    let end = LorvexDateFormatters.ymdUTCAddingDays(anchorDay, days: 7) ?? anchorDay
    calendarTimelineLoadToken &+= 1
    let token = calendarTimelineLoadToken
    do {
      await ingestEventKitWindow(fromDay: start, throughDay: end)
      let timeline = try await core.loadCalendarTimeline(from: start, to: end)
      let tasks = try await core.getScheduledTasks(from: start, to: end, limit: 500)
      // A newer window superseded this load while it was in flight; committing
      // now would pair this window's events with a different window's scheduled
      // tasks, so discard the stale result.
      guard token == calendarTimelineLoadToken else { return }
      calendarTimeline = timeline
      calendarScheduledTasks = tasks
      errorMessage = nil
    } catch {
      guard token == calendarTimelineLoadToken else { return }
      await presentUserFacingError(error)
    }
  }

  /// Reconciles the exact already-visible calendar window after an explicit
  /// Settings change. EventKit errors are surfaced to the Settings caller, but
  /// the canonical timeline is still re-read first: permission revocation and
  /// privacy-tier downgrades clear the provider mirror before throwing, so the
  /// in-memory view must adopt that cleared state rather than retain old detail.
  func refreshCalendarTimelineForSettings(
    fromDay: String,
    throughDay: String,
    requestAccess: Bool
  ) async throws {
    calendarTimelineLoadToken &+= 1
    let token = calendarTimelineLoadToken
    let ingestError: (any Error)?
    do {
      try await ingestEventKitWindowThrowing(
        fromDay: fromDay,
        throughDay: throughDay,
        requestAccess: requestAccess)
      ingestError = nil
    } catch {
      ingestError = error
    }

    let timeline = try await core.loadCalendarTimeline(from: fromDay, to: throughDay)
    let tasks = try await core.getScheduledTasks(from: fromDay, to: throughDay, limit: 500)
    guard token == calendarTimelineLoadToken else { return }
    calendarTimeline = timeline
    calendarScheduledTasks = tasks
    if let ingestError { throw ingestError }
    errorMessage = nil
  }

  public func exportCalendarICS() async -> String? {
    guard !isExportingCalendarICS else { return nil }
    isExportingCalendarICS = true
    defer { isExportingCalendarICS = false }

    do {
      let ics = try await core.exportCalendarICS(
        from: calendarTimeline?.from,
        to: calendarTimeline?.to
      )
      errorMessage = nil
      return ics
    } catch {
      await presentUserFacingError(error)
      return nil
    }
  }
}
