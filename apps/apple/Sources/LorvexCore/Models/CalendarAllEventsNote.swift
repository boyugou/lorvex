import Foundation

/// Decides whether the save prompt for a repeating event adds a note about what
/// its All Events choice does to single-occurrence changes.
///
/// Saving with All Events applies the draft to the whole series. It resets every
/// occurrence the user changed on its own to the series values, and occurrences
/// that were cancelled stay cancelled. The note says so only when the reset
/// would discard a change the user can see in the calendar, so an event without
/// such changes keeps the short prompt.
public enum CalendarAllEventsNote {
  /// True when saving `draft` over the repeating `occurrence` with All Events
  /// would reset a single-occurrence change of the same series that is visible
  /// in `loadedEvents`.
  ///
  /// - An occurrence counts as changed when its
  ///   ``CalendarTimelineEvent/occurrenceState`` is `.replacement`. Cancelled
  ///   occurrences are not part of a timeline, so they never count.
  /// - The series is matched by ``CalendarTimelineEvent/eventID``, which is the
  ///   series' own id on every one of its occurrences, so a changed occurrence
  ///   of another series never counts.
  /// - `occurrence` counts on its own, so opening a changed occurrence needs no
  ///   other event in `loadedEvents`.
  /// - A draft that moves the series' first day or changes its length in days
  ///   (see ``CalendarEventTiming/keepsSeriesFirstDay(of:)``), or that changes
  ///   the repeat rule (any `recurrence` other than `.unset`), restarts the
  ///   recurrence and clears every change and cancellation, so the answer is
  ///   false.
  public static func isShown(
    editing occurrence: CalendarTimelineEvent,
    draft: CalendarEventTiming,
    recurrence: CalendarEventRecurrencePatch = .unset,
    loadedEvents: [CalendarTimelineEvent]
  ) -> Bool {
    guard recurrence == .unset, draft.keepsSeriesFirstDay(of: occurrence) else { return false }
    if occurrence.occurrenceState == .replacement { return true }
    return loadedEvents.contains {
      $0.occurrenceState == .replacement && $0.eventID == occurrence.eventID
    }
  }
}
