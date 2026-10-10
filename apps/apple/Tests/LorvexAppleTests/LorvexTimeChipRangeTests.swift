import Foundation
import Testing

@testable import LorvexApple

private func source(_ path: String) throws -> String {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: path)
  return try String(contentsOf: url, encoding: .utf8)
}

struct LorvexTimeChipRangeTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
  }

  private func time(_ hour: Int, _ minute: Int, day: Int = 10) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))
      ?? Date()
  }

  @Test func aRangeInsideTheDayBecomesItsMinutesOfTheDay() {
    let range = time(0, 0)...time(22, 59)
    #expect(
      LorvexTimeChipPopover.allowedMinutes(for: range, on: time(8, 0), calendar: calendar)
        == 0...(22 * 60 + 59))
    #expect(
      LorvexTimeChipPopover.allowedMinutes(for: nil, on: time(8, 0), calendar: calendar) == nil)
  }

  @Test func aBoundOnAnotherDayClipsToTheEdgeOfThisDay() {
    let earlier = time(23, 0, day: 9)...time(9, 30)
    #expect(
      LorvexTimeChipPopover.allowedMinutes(for: earlier, on: time(8, 0), calendar: calendar)
        == 0...(9 * 60 + 30))
    let later = time(8, 1)...time(0, 0, day: 11)
    #expect(
      LorvexTimeChipPopover.allowedMinutes(for: later, on: time(8, 0), calendar: calendar)
        == (8 * 60 + 1)...1439)
  }

  @Test func aRangeThatLeavesNoTimeOfTheDayAllowsNothingToClip() {
    let nextDay = time(0, 0, day: 11)...time(6, 0, day: 11)
    #expect(
      LorvexTimeChipPopover.allowedMinutes(for: nextDay, on: time(8, 0), calendar: calendar) == nil)
  }

  @Test func aChoiceOutsideTheRangeLandsOnTheNearestAllowedMinute() {
    let allowed = (8 * 60 + 1)...(23 * 60 + 59)
    #expect(LorvexTimeChipPopover.clamped(7 * 60, to: allowed) == 8 * 60 + 1)
    #expect(LorvexTimeChipPopover.clamped(12 * 60, to: allowed) == 12 * 60)
    #expect(LorvexTimeChipPopover.clamped(24 * 60, to: allowed) == 23 * 60 + 59)
    #expect(LorvexTimeChipPopover.clamped(7 * 60, to: nil) == 7 * 60)
  }

  @Test func theDayHoursChipsAreBoundedAndTheEventChipsAreNot() throws {
    // Day Hours needs the end after the start, so both of its chips carry a range. An event may
    // end before it starts (it runs into the next day and the form warns), so its chips do not.
    let row = try source("Sources/LorvexApple/Views/SettingsWorkingHoursRow.swift")
    #expect(row.components(separatedBy: "allowedRange: Self.window(").count == 3)
    let event = try source("Sources/LorvexApple/Views/CalendarEventFormFields.swift")
    #expect(!event.contains("allowedRange"))
  }
}
