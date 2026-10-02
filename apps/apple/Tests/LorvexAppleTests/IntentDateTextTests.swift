import Foundation
import LorvexCore
import Testing

@testable import LorvexSystemIntents

@Test
func intentDateTextReadsTheDayAndTimeInTheDeviceTimeZone() throws {
  // A late-evening instant on the device clock: reading it in UTC would move
  // the day east of Greenwich, so this pins the device-zone reading.
  let calendar = Calendar(identifier: .gregorian)
  let lateEvening = try #require(
    calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 23, minute: 45)))
  #expect(IntentDateText.day(lateEvening) == "2026-10-05")
  #expect(IntentDateText.time(lateEvening) == "23:45")

  let earlyMorning = try #require(
    calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 0, minute: 5)))
  #expect(IntentDateText.day(earlyMorning) == "2026-10-06")
  #expect(IntentDateText.time(earlyMorning) == "00:05")
}

@Test
func intentDateTextPutsARangePickedBackwardsInOrder() throws {
  let first = try #require(LorvexDateFormatters.ymd.date(from: "2026-10-01"))
  let last = try #require(LorvexDateFormatters.ymd.date(from: "2026-10-09"))

  let backwards = IntentDateText.dayRange(from: last, to: first)
  #expect(backwards.from == "2026-10-01")
  #expect(backwards.to == "2026-10-09")

  let forwards = IntentDateText.dayRange(from: first, to: last)
  #expect(forwards.from == "2026-10-01")
  #expect(forwards.to == "2026-10-09")

  let openStart = IntentDateText.dayRange(from: nil, to: first)
  #expect(openStart.from == nil)
  #expect(openStart.to == "2026-10-01")

  let openEnd = IntentDateText.dayRange(from: last, to: nil)
  #expect(openEnd.from == "2026-10-09")
  #expect(openEnd.to == nil)
}

@Test
func intentDateTextWritesAMomentAsAUTCTimestamp() throws {
  let moment = try #require(LorvexDateFormatters.iso8601.date(from: "2026-10-05T16:30:00Z"))
  #expect(IntentDateText.timestamp(moment) == "2026-10-05T16:30:00Z")
}

@Test
func weekdayAndPriorityOptionsMapToTheValuesLorvexStores() {
  #expect(
    LorvexWeekdayOption.allCases.map(\.ruleCode) == ["MO", "TU", "WE", "TH", "FR", "SA", "SU"])
  #expect(LorvexPriorityOption.allCases.map(\.level) == [1, 2, 3])
}
