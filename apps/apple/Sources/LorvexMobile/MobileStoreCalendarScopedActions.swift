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
        updates: scopedUpdatesFromDraft()
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

  /// The draft's editable fields as a scoped-edit patch. Omitted fields (endDate)
  /// preserve the original; empty location / notes strings clear those fields,
  /// matching the whole-object `updateCalendarEvent` contract.
  private func scopedUpdatesFromDraft() -> ScopedCalendarEventUpdates {
    ScopedCalendarEventUpdates(
      title: calendarDraft.trimmedTitle,
      startDate: Self.ymdFormatter.string(from: calendarDraft.date),
      endDate: nil,
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
    guard let from = calendarTimeline?.from, let to = calendarTimeline?.to else { return }
    do {
      calendarTimeline = try await core.loadCalendarTimeline(from: from, to: to)
    } catch {
      await presentUserFacingError(error)
    }
  }
}
