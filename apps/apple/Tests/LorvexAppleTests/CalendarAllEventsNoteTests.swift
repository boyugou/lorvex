import Foundation
import LorvexCore
import Testing

private let noteCalendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
  return calendar
}()

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
  noteCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
    ?? .distantPast
}

/// One occurrence of the repeating series `series` as the calendar timeline lists
/// it: every occurrence carries the series' id as its `eventID`, and a changed
/// one has the `.replacement` state.
private func occurrence(
  of series: String, on date: String, state: CalendarTimelineOccurrenceState? = nil
) -> CalendarTimelineEvent {
  CalendarTimelineEvent(
    id: "\(series)-\(date)-\(state?.rawValue ?? "natural")", eventID: series, seriesID: series,
    occurrenceDate: date, occurrenceState: state, title: "Daily planning", source: "canonical",
    editable: true, startDate: date, startTime: "09:00", endDate: nil, endTime: "10:00",
    allDay: false, location: nil, color: nil, eventType: "event", timezone: nil,
    isRecurring: true)
}

private func draft(for event: CalendarTimelineEvent) -> CalendarEventTiming {
  CalendarEventTiming(event: event, fallbackDay: at(2026, 1, 1), calendar: noteCalendar)
}

/// The All Events note belongs to the save prompt of a repeating event. It shows
/// only when All Events would reset a single-occurrence change that the loaded
/// calendar timeline lists.
@Suite("Calendar All Events note")
struct CalendarAllEventsNoteTests {
  private let edited = occurrence(of: "series-a", on: "2026-10-08")

  @Test("a changed occurrence of the same series shows the note")
  func aChangedOccurrenceOfTheSameSeriesShowsTheNote() {
    let loaded = [
      occurrence(of: "series-a", on: "2026-10-07"),
      edited,
      occurrence(of: "series-a", on: "2026-10-09", state: .replacement),
    ]
    #expect(
      CalendarAllEventsNote.isShown(
        editing: edited, draft: draft(for: edited), loadedEvents: loaded))
  }

  @Test("a changed occurrence open for editing shows the note without other events")
  func theEditedOccurrenceCountsOnItsOwn() {
    let changed = occurrence(of: "series-a", on: "2026-10-08", state: .replacement)
    #expect(
      CalendarAllEventsNote.isShown(
        editing: changed, draft: draft(for: changed), loadedEvents: []))
  }

  @Test("a changed occurrence of another series does not show the note")
  func aChangedOccurrenceOfAnotherSeriesDoesNotShowTheNote() {
    let loaded = [
      edited,
      occurrence(of: "series-b", on: "2026-10-08", state: .replacement),
      occurrence(of: "series-b", on: "2026-10-09", state: .replacement),
    ]
    #expect(
      !CalendarAllEventsNote.isShown(
        editing: edited, draft: draft(for: edited), loadedEvents: loaded))
  }

  @Test("a series without a changed occurrence does not show the note")
  func aSeriesWithoutAChangedOccurrenceDoesNotShowTheNote() {
    let loaded = [
      occurrence(of: "series-a", on: "2026-10-07"),
      edited,
      occurrence(of: "series-a", on: "2026-10-09"),
    ]
    #expect(
      !CalendarAllEventsNote.isShown(
        editing: edited, draft: draft(for: edited), loadedEvents: loaded))
    #expect(
      !CalendarAllEventsNote.isShown(
        editing: edited, draft: draft(for: edited), loadedEvents: []))
  }

  @Test("cancelled and inherited decisions do not count as changed occurrences")
  func cancelledAndInheritedDecisionsDoNotCount() {
    let loaded = [
      edited,
      occurrence(of: "series-a", on: "2026-10-09", state: .cancelled),
      occurrence(of: "series-a", on: "2026-10-10", state: .inherit),
    ]
    #expect(
      !CalendarAllEventsNote.isShown(
        editing: edited, draft: draft(for: edited), loadedEvents: loaded))
  }

  @Test("a time-only edit keeps the note")
  func aTimeOnlyEditKeepsTheNote() {
    let loaded = [edited, occurrence(of: "series-a", on: "2026-10-09", state: .replacement)]
    var timing = draft(for: edited)
    timing.setStartTime(at(2000, 1, 1, 8))
    #expect(CalendarAllEventsNote.isShown(editing: edited, draft: timing, loadedEvents: loaded))
  }

  @Test("a moved first day or a changed length in days does not show the note")
  func aMovedFirstDayOrASpanChangeDoesNotShowTheNote() {
    let loaded = [edited, occurrence(of: "series-a", on: "2026-10-09", state: .replacement)]

    var moved = draft(for: edited)
    moved.setStartDay(at(2026, 10, 15))
    #expect(!CalendarAllEventsNote.isShown(editing: edited, draft: moved, loadedEvents: loaded))

    var longer = draft(for: edited)
    longer.setEndDay(at(2026, 10, 9))
    #expect(!CalendarAllEventsNote.isShown(editing: edited, draft: longer, loadedEvents: loaded))
  }

  @Test("a changed repeat rule does not show the note")
  func aChangedRepeatRuleDoesNotShowTheNote() {
    let loaded = [edited, occurrence(of: "series-a", on: "2026-10-09", state: .replacement)]
    let timing = draft(for: edited)

    #expect(
      CalendarAllEventsNote.isShown(
        editing: edited, draft: timing, recurrence: .unset, loadedEvents: loaded))
    #expect(
      !CalendarAllEventsNote.isShown(
        editing: edited, draft: timing, recurrence: .clear, loadedEvents: loaded))
    #expect(
      !CalendarAllEventsNote.isShown(
        editing: edited, draft: timing, recurrence: .set(TaskRecurrenceRule(freq: .weekly)),
        loadedEvents: loaded))
  }
}
