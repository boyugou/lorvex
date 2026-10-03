import Foundation
import LorvexCore

/// A calendar timeline window as `yyyy-MM-dd` day keys, both ends inclusive.
struct MobileCalendarWindow: Equatable, Sendable {
  let from: String
  let to: String
}

extension MobileStore {
  /// Shows the calendar in `mode`, opening on `dayKey` (`yyyy-MM-dd`), and
  /// remembers the mode so the next store opens the calendar in it. Switching
  /// to the mode already shown does nothing.
  func switchCalendarPresentationMode(
    to mode: MobileCalendarPresentationMode, onDayKey dayKey: String
  ) {
    guard mode != calendarPresentationMode else { return }
    calendarPendingDayKey = dayKey
    calendarPresentationMode = mode
    defaults.set(mode.rawValue, forKey: MobileCalendarPresentationMode.defaultsKey)
  }

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
          startDate: calendarDraft.timing.startDate,
          endDate: calendarDraft.timing.endDate,
          startTime: calendarDraft.timing.startTime,
          endTime: calendarDraft.timing.endTime,
          allDay: calendarDraft.timing.allDay,
          location: calendarDraft.trimmedLocation.trimmedNilIfEmpty,
          notes: calendarDraft.trimmedNotes.trimmedNilIfEmpty
        )
      })
    else { return false }

    calendarDraft = MobileCalendarDraft(now: now)
    await reconcileAfterCommittedMutation(source: "ios.calendar.create.reconcile") {
      // Reconcile the window the user is actually viewing, not a today-anchored
      // one: the day view loads `[visibleDate-7, visibleDate+7]`, so reloading a
      // fixed `[today, today+14]` here would drop every pre-existing event in a
      // week the user paged away to. Matches the scoped-mutation and macOS
      // reconcile paths. Falls back to the today window only when no timeline is
      // loaded (a create raised before the timeline first loads).
      let from = calendarWindowToReload?.from ?? logicalTodayString
      let to = calendarWindowToReload?.to ?? Self.calendarEndDateString(from: logicalTodayString)
      calendarTimeline = try await core.loadCalendarTimeline(from: from, to: to)
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
  /// generic "New Event" affordance: an untitled one-hour event from the next
  /// full hour, matching the macOS toolbar default. `calendarDraft` is reused by
  /// the edit flow (``prepareCalendarDraft(for:)``) and by day-grid taps, so a
  /// create sheet opened from the toolbar would otherwise inherit the last
  /// edited or tapped-slot draft. Day-grid taps seed their own time slot and
  /// bypass this.
  public func beginCreateCalendarDraft() {
    calendarDraft = MobileCalendarDraft(timing: .nextHourBlock(after: now()))
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
        startDate: calendarDraft.timing.startDate,
        endDate: calendarDraft.timing.endDate(updating: event.endDate),
        startTime: calendarDraft.timing.startTime,
        endTime: calendarDraft.timing.endTime,
        allDay: calendarDraft.timing.allDay,
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
    // Same multi-day guard as the macOS path: a multi-day event shows one
    // piece per day, which a drag cannot move as a whole. An event that ends
    // at midnight is a one-day event and does move.
    guard event.editable, !event.allDay, !event.supportsScopedMutation,
      !event.isMultiDay, !isMutatingCalendarEvent
    else { return false }
    isMutatingCalendarEvent = true
    defer { isMutatingCalendarEvent = false }
    let timing = CalendarEventTiming(start: newStart, end: newEnd, allDay: false)
    do {
      let updated = try await core.updateCalendarEvent(
        id: event.eventID,
        title: event.title,
        startDate: timing.startDate,
        // The end date moves with the drop: the dropped day, or the next one
        // for a drop that runs past midnight. An event that had an end date
        // and now fits in one day sends its start date, since nil keeps the
        // stored end on the original day, which throws "end before start" when
        // a drag across day columns (iPad) moves forward and stretches the
        // event when it moves back.
        endDate: timing.endDate(updating: event.endDate),
        startTime: timing.startTime,
        endTime: timing.endTime,
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
  /// view. Fetches `radiusDays` each side (a week by default) so horizontal swipes in either
  /// direction render without an immediate refetch; the day view re-invokes
  /// this when the visible date nears the window edge. Reuses the existing
  /// `loadCalendarTimeline` core read — no new data path.
  func refreshCalendarTimeline(around anchor: Date, radiusDays: Int = 7) async {
    let anchorDay = Self.ymdFormatter.string(from: anchor)
    let start = LorvexDateFormatters.ymdUTCAddingDays(anchorDay, days: -radiusDays) ?? anchorDay
    let end = LorvexDateFormatters.ymdUTCAddingDays(anchorDay, days: radiusDays) ?? anchorDay
    await refreshCalendarTimeline(from: start, to: end)
  }

  /// Reload the window the day view currently owns rather than re-anchoring to a
  /// fixed date. Falls back to a window around `fallbackAnchor` only when no
  /// timeline is loaded yet. A background `.EKEventStoreChanged` and a CloudKit
  /// inbound reload both fire while the user may be browsing a far week; using
  /// this instead of `refreshCalendarTimeline(around: now())` refreshes that
  /// week in place instead of snapping the loaded window back to today (which
  /// would silently empty the viewed days until a >5-day page turn).
  func refreshLoadedCalendarWindow(fallbackAnchor: Date) async {
    if let window = calendarWindowToReload {
      await refreshCalendarTimeline(from: window.from, to: window.to)
    } else {
      await refreshCalendarTimeline(around: fallbackAnchor)
    }
  }

  /// Ingest, load, and commit a specific calendar window under the shared
  /// supersede token so a slower in-flight load can never pair one window's
  /// events with another window's scheduled tasks.
  func refreshCalendarTimeline(from start: String, to end: String) async {
    calendarRequestedWindow = MobileCalendarWindow(from: start, to: end)
    calendarTimelineLoadToken &+= 1
    let token = calendarTimelineLoadToken
    do {
      await ingestEventKitWindow(fromDay: start, throughDay: end)
      let timeline = try await core.loadCalendarTimeline(from: start, to: end)
      let tasks = try await core.getScheduledTasks(
        from: start, to: end, limit: CalendarGridModel.windowTaskLimit)
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

  /// The window a refresh reloads: the one the calendar surface last asked
  /// for, even while that load is still in flight, else the loaded one. Nil
  /// before any calendar load, when a refresh falls back to a today window.
  var calendarWindowToReload: MobileCalendarWindow? {
    calendarRequestedWindow ?? calendarTimeline.map { MobileCalendarWindow(from: $0.from, to: $0.to) }
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
    calendarRequestedWindow = MobileCalendarWindow(from: fromDay, to: throughDay)
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
    let tasks = try await core.getScheduledTasks(
      from: fromDay, to: throughDay, limit: CalendarGridModel.windowTaskLimit)
    guard token == calendarTimelineLoadToken else { return }
    calendarTimeline = timeline
    calendarScheduledTasks = tasks
    if let ingestError { throw ingestError }
    errorMessage = nil
  }

  /// The user's events from the logical today through the next 30 days as
  /// `.ics` text (the core's default export range), or `nil` after surfacing
  /// an error. Settings › Data Export offers it, so it never depends on which
  /// window the calendar last loaded.
  public func exportCalendarICS() async -> String? {
    guard !isExportingCalendarICS else { return nil }
    isExportingCalendarICS = true
    defer { isExportingCalendarICS = false }

    do {
      let ics = try await core.exportCalendarICS(from: nil, to: nil)
      errorMessage = nil
      return ics
    } catch {
      await presentUserFacingError(error)
      return nil
    }
  }
}
