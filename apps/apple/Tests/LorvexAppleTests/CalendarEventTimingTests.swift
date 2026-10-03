import Foundation
import LorvexCore
import Testing

private let timingCalendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
  return calendar
}()

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
  timingCalendar.date(
    from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
    ?? .distantPast
}

private func storedEvent(
  start: String, startTime: String? = nil, end: String? = nil, endTime: String? = nil,
  allDay: Bool = false
) -> CalendarTimelineEvent {
  CalendarTimelineEvent(
    id: "event", title: "Night shift", source: "canonical", editable: true, startDate: start,
    startTime: startTime, endDate: end, endTime: endTime, allDay: allDay, location: nil,
    color: nil, eventType: "event", timezone: nil, isRecurring: false)
}

private func timing(_ event: CalendarTimelineEvent) -> CalendarEventTiming {
  CalendarEventTiming(event: event, fallbackDay: at(2026, 1, 1), calendar: timingCalendar)
}

@Test
func eventTimingReadsOvernightAndMultiDayEvents() {
  let overnight = timing(
    storedEvent(start: "2026-10-02", startTime: "22:00", end: "2026-10-03", endTime: "01:00"))
  #expect(overnight.start == at(2026, 10, 2, 22))
  #expect(overnight.end == at(2026, 10, 3, 1))
  #expect(overnight.isValid)
  #expect(overnight.daySpan == 1)
  #expect(overnight.startDate == "2026-10-02")
  #expect(overnight.endDate == "2026-10-03")
  #expect(overnight.startTime == "22:00")
  #expect(overnight.endTime == "01:00")

  // An all-day event has no clock times; it offers 09:00 to 10:00 for when
  // All Day is turned off, and its end date is its last day.
  let trip = timing(storedEvent(start: "2026-10-02", end: "2026-10-04", allDay: true))
  #expect(trip.start == at(2026, 10, 2, 9))
  #expect(trip.end == at(2026, 10, 4, 10))
  #expect(trip.endDate == "2026-10-04")
  #expect(trip.startTime == nil)
  #expect(trip.endTime == nil)

  // No end time runs one hour; an end date before the start reads as the start.
  let open = timing(storedEvent(start: "2026-10-02", startTime: "09:30"))
  #expect(open.end == at(2026, 10, 2, 10, 30))
  let backwards = timing(storedEvent(start: "2026-10-02", end: "2026-09-30", allDay: true))
  #expect(backwards.endDate == nil)
}

@Test
func movingTheStartKeepsTheLengthInClockTime() {
  var shift = timing(
    storedEvent(start: "2026-10-02", startTime: "22:00", end: "2026-10-03", endTime: "01:00"))
  shift.setStartTime(at(2000, 1, 1, 21, 30))
  #expect(shift.start == at(2026, 10, 2, 21, 30))
  #expect(shift.end == at(2026, 10, 3, 0, 30))
  shift.setStartDay(at(2026, 10, 9))
  #expect(shift.start == at(2026, 10, 9, 21, 30))
  #expect(shift.end == at(2026, 10, 10, 0, 30))

  // 23:00 to 02:00 across the night clocks fall back is still 23:00 to 02:00
  // after a move to a night without a change.
  var fallBack = timing(
    storedEvent(start: "2026-10-31", startTime: "23:00", end: "2026-11-01", endTime: "02:00"))
  fallBack.setStartDay(at(2026, 10, 24))
  #expect(fallBack.start == at(2026, 10, 24, 23))
  #expect(fallBack.end == at(2026, 10, 25, 2))

  var trip = timing(storedEvent(start: "2026-10-02", end: "2026-10-04", allDay: true))
  trip.moveStart(to: at(2026, 12, 30, 9))
  #expect(trip.startDate == "2026-12-30")
  #expect(trip.endDate == "2027-01-01")
}

@Test
func anEndTimeBeforeTheStartRunsTheEventOvernight() {
  var event = CalendarEventTiming(
    start: at(2026, 10, 2, 22), end: at(2026, 10, 2, 23), allDay: false, calendar: timingCalendar)
  event.setEndTime(at(2000, 1, 1, 1))
  #expect(event.end == at(2026, 10, 3, 1))
  // Picking a later time again brings the end back to the start day.
  event.setEndTime(at(2000, 1, 1, 23, 30))
  #expect(event.end == at(2026, 10, 2, 23, 30))
  // The start's own clock time is a full day later, never a zero-length event.
  event.setEndTime(at(2000, 1, 1, 22))
  #expect(event.end == at(2026, 10, 3, 22))

  // An event that ends two or more days after it starts keeps its end day.
  var conference = CalendarEventTiming(
    start: at(2026, 10, 2, 9), end: at(2026, 10, 4, 17), allDay: false, calendar: timingCalendar)
  conference.setEndTime(at(2000, 1, 1, 8))
  #expect(conference.end == at(2026, 10, 4, 8))
  #expect(conference.isValid)
}

@Test
func aPickerEndTellsADayChangeFromATimeChange() {
  var event = CalendarEventTiming(
    start: at(2026, 10, 2, 22), end: at(2026, 10, 3, 1), allDay: false, calendar: timingCalendar)
  // Same day as the current end: a clock-time change, so it follows the start.
  event.setEnd(at(2026, 10, 3, 23))
  #expect(event.end == at(2026, 10, 2, 23))
  // Another day: kept as picked.
  event.setEnd(at(2026, 10, 5, 1))
  #expect(event.end == at(2026, 10, 5, 1))
  event.setEndDay(at(2026, 10, 1))
  #expect(event.end == at(2026, 10, 1, 1))
  #expect(!event.isValid)
}

@Test
func oneDayEventsStoreNoEndDateAndUpdatesWriteItOut() {
  let evening = CalendarEventTiming(
    start: at(2026, 10, 2, 18), end: at(2026, 10, 2, 19), allDay: false, calendar: timingCalendar)
  #expect(evening.endDate == nil)
  #expect(evening.endDate(updating: nil) == nil)
  // An event that had an end date sends the start date: nil would keep it.
  #expect(evening.endDate(updating: "2026-10-03") == "2026-10-02")

  // Ending exactly at midnight stores the next day at 00:00.
  let late = CalendarEventTiming(
    start: at(2026, 10, 2, 23), end: at(2026, 10, 3), allDay: false, calendar: timingCalendar)
  #expect(late.endDate == "2026-10-03")
  #expect(late.endTime == "00:00")

  let allDay = CalendarEventTiming(
    start: at(2026, 10, 2, 9), end: at(2026, 10, 2, 8), allDay: true, calendar: timingCalendar)
  #expect(allDay.isValid)
  #expect(!CalendarEventTiming(
    start: at(2026, 10, 2, 9), end: at(2026, 10, 2, 9), allDay: false, calendar: timingCalendar
  ).isValid)
}

@Test
func scopedEditsSendDatesOnlyWhenTheDayOrTheSpanChanges() {
  let occurrence = storedEvent(
    start: "2026-10-02", startTime: "22:00", end: "2026-10-03", endTime: "01:00")
  var shift = timing(occurrence)
  #expect(shift.scopedDates(for: occurrence) == (nil, nil))
  shift.setStartTime(at(2000, 1, 1, 21))
  #expect(shift.scopedDates(for: occurrence) == (nil, nil))
  #expect(shift.keepsDaySpan(of: occurrence))

  // Ending the same evening changes the span: the dates are written out.
  shift.setEndTime(at(2000, 1, 1, 23))
  #expect(!shift.keepsDaySpan(of: occurrence))
  #expect(shift.scopedDates(for: occurrence) == ("2026-10-02", "2026-10-02"))

  var moved = timing(occurrence)
  moved.setStartDay(at(2026, 10, 9))
  #expect(moved.keepsDaySpan(of: occurrence))
  #expect(moved.scopedDates(for: occurrence) == ("2026-10-09", "2026-10-10"))

  #expect(CalendarEventTiming.daySpan(startDate: "2026-12-31", endDate: "2027-01-02") == 2)
  #expect(CalendarEventTiming.daySpan(startDate: "2026-10-02", endDate: nil) == 0)
}

@Test
func aNewEventStartsOnTheNextFullHour() {
  let afternoon = CalendarEventTiming.nextHourBlock(
    after: at(2026, 10, 2, 14, 23), calendar: timingCalendar)
  #expect(afternoon.start == at(2026, 10, 2, 15))
  #expect(afternoon.end == at(2026, 10, 2, 16))
  #expect(!afternoon.allDay)

  let onTheHour = CalendarEventTiming.nextHourBlock(
    after: at(2026, 10, 2, 14), calendar: timingCalendar)
  #expect(onTheHour.start == at(2026, 10, 2, 14))

  // Late in the evening the block runs past midnight instead of shrinking.
  let late = CalendarEventTiming.timed(
    startingAt: at(2026, 10, 2, 23, 30), calendar: timingCalendar)
  #expect(late.end == at(2026, 10, 3, 0, 30))
  #expect(late.isValid)
}

// A timed event that ends at exactly midnight takes time on its start day
// only, so the calendar grids show and drag it as a one-day block. Moving it
// keeps its length within the day, and the update writes the start day as the
// end date in place of the stored next-day end.
@Test
func anEventThatEndsAtMidnightIsAOneDayEvent() {
  let toMidnight = storedEvent(
    start: "2026-10-02", startTime: "21:00", end: "2026-10-03", endTime: "00:00")
  #expect(!toMidnight.isMultiDay)
  #expect(storedEvent(
    start: "2026-10-02", startTime: "23:00", end: "2026-10-03", endTime: "01:00"
  ).isMultiDay)
  #expect(storedEvent(
    start: "2026-10-02", startTime: "22:00", end: "2026-10-04", endTime: "00:00"
  ).isMultiDay)
  #expect(!storedEvent(
    start: "2026-10-02", startTime: "09:00", end: "2026-10-02", endTime: "10:00"
  ).isMultiDay)
  #expect(!storedEvent(start: "2026-10-02", startTime: "09:00", endTime: "10:00").isMultiDay)
  #expect(storedEvent(start: "2026-10-02", end: "2026-10-03", allDay: true).isMultiDay)
  #expect(!storedEvent(start: "2026-10-02", allDay: true).isMultiDay)

  var moved = timing(toMidnight)
  moved.moveStart(to: at(2026, 10, 2, 20))
  #expect(moved.end == at(2026, 10, 2, 23))
  #expect(moved.endDate == nil)
  #expect(moved.endDate(updating: toMidnight.endDate) == "2026-10-02")
}
