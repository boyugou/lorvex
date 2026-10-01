import Foundation
import LorvexCore

extension MobileStore {
  /// Save the current calendar draft to a recurring event with the chosen
  /// ``CalendarEventEditScope``. Every scope routes through the core's scoped
  /// workflow and addresses the original recurrence slot, even when the visible
  /// replacement has moved to another date.
  @discardableResult
  public func saveScopedCalendarEvent(
    _ event: CalendarTimelineEvent, scope: CalendarEventEditScope
  ) async -> Bool {
    guard event.editable, event.supportsScopedMutation, canUpdateCalendarDraft,
      let occurrenceDate = event.occurrenceDate
    else { return false }
    isMutatingCalendarEvent = true
    defer { isMutatingCalendarEvent = false }
    do {
      _ = try await core.editScopedCalendarEvent(
        eventID: event.eventID,
        occurrenceDate: occurrenceDate,
        scope: scope.rawValue,
        updates: scopedUpdatesFromDraft(for: event)
      )
      calendarDraft = MobileCalendarDraft(now: now)
      errorMessage = nil
      await reloadCalendarWindowAfterScopedMutation()
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  /// Delete a recurring event with the chosen scope. `allEvents` removes the
  /// whole series; narrower scopes cancel one occurrence or truncate the series.
  @discardableResult
  public func deleteScopedCalendarEvent(
    _ event: CalendarTimelineEvent, scope: CalendarEventEditScope
  ) async -> Bool {
    guard event.editable, event.supportsScopedMutation,
      let occurrenceDate = event.occurrenceDate
    else { return false }
    guard !isMutatingCalendarEvent else { return false }
    isMutatingCalendarEvent = true
    defer { isMutatingCalendarEvent = false }
    do {
      _ = try await core.deleteScopedCalendarEvent(
        eventID: event.eventID,
        occurrenceDate: occurrenceDate,
        scope: scope.rawValue
      )
      errorMessage = nil
      await reloadCalendarWindowAfterScopedMutation()
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  /// The draft's editable fields as a scoped-edit patch. `startDate`/`endDate`
  /// are sent only when the user actually changed the day: the draft is seeded
  /// with THIS occurrence's date, and for `.allEvents`/segment scopes sending it
  /// unchanged would re-anchor the whole series to this occurrence's day on a
  /// metadata-only edit (dropping earlier occurrences). When the day did change,
  /// the end shifts with it (``shiftedCalendarEndDate(for:newStartDate:)``) so it
  /// never strands. Empty location / notes strings clear those fields, matching
  /// the whole-object `updateCalendarEvent` contract.
  private func scopedUpdatesFromDraft(for event: CalendarTimelineEvent)
    -> ScopedCalendarEventUpdates
  {
    let newStartYmd = Self.ymdFormatter.string(from: calendarDraft.date)
    let dateChanged = newStartYmd != event.startDate
    return ScopedCalendarEventUpdates(
      title: calendarDraft.trimmedTitle,
      startDate: dateChanged ? newStartYmd : nil,
      endDate: dateChanged
        ? shiftedCalendarEndDate(for: event, newStartDate: calendarDraft.date) : nil,
      startTime: calendarDraft.allDay
        ? nil : Self.hmFormatter.string(from: calendarDraft.startTime),
      endTime: calendarDraft.allDay
        ? nil : Self.hmFormatter.string(from: calendarDraft.endTime),
      allDay: calendarDraft.allDay,
      location: calendarDraft.trimmedLocation,
      notes: calendarDraft.trimmedNotes
    )
  }

  /// Re-fetch the currently loaded timeline window after a scoped mutation, which
  /// can split a series or create a one-off replacement — changes an in-place
  /// single-event update cannot capture.
  private func reloadCalendarWindowAfterScopedMutation() async {
    guard let window = calendarWindowToReload else { return }
    do {
      calendarTimeline = try await core.loadCalendarTimeline(from: window.from, to: window.to)
    } catch {
      await presentUserFacingError(error)
    }
  }
}
