import Foundation
import Testing

@testable import LorvexApple

/// The reminder editor's one-click times on macOS
/// (`TaskDetailReminderPreset.presets`).
struct TaskDetailReminderPresetTests {
  private static func zone(_ identifier: String) throws -> TimeZone {
    try #require(TimeZone(identifier: identifier))
  }

  private static func midnight(_ year: Int, _ month: Int, _ day: Int, in zone: TimeZone) throws
    -> Date
  {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
  }

  private static func instant(_ iso: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: iso))
  }

  /// A device in New York shows a product zone of Los Angeles: the pickers'
  /// days are New York midnights, which are still the evening before in Los
  /// Angeles. The reminders stay on the days the pickers name.
  @Test
  func presetsKeepThePickedDaysWhenTheProductZoneIsWestOfTheDevice() throws {
    let newYork = try Self.zone("America/New_York")
    let losAngeles = try Self.zone("America/Los_Angeles")
    let presets = TaskDetailReminderPreset.presets(
      plannedDay: try Self.midnight(2026, 10, 5, in: newYork),
      plannedTime: 14 * 60..<15 * 60,
      dueDay: try Self.midnight(2026, 10, 6, in: newYork),
      now: try Self.instant("2026-10-03T19:00:00Z"),
      timeZone: losAngeles,
      pickerTimeZone: newYork)
    let dates = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0.date) })

    #expect(presets.map(\.id) == ["start", "due", "hour", "tomorrow"])
    // 2 PM and 9 AM Pacific daylight time on the picked days.
    #expect(dates["start"] == (try Self.instant("2026-10-05T21:00:00Z")))
    #expect(dates["due"] == (try Self.instant("2026-10-06T16:00:00Z")))
    #expect(dates["hour"] == (try Self.instant("2026-10-03T20:00:00Z")))
    #expect(dates["tomorrow"] == (try Self.instant("2026-10-04T16:00:00Z")))
  }

  @Test
  func presetsKeepThePickedDaysWhenTheProductZoneIsEastOfTheDevice() throws {
    let losAngeles = try Self.zone("America/Los_Angeles")
    let tokyo = try Self.zone("Asia/Tokyo")
    let presets = TaskDetailReminderPreset.presets(
      plannedDay: try Self.midnight(2026, 10, 5, in: losAngeles),
      plannedTime: 14 * 60..<15 * 60,
      dueDay: nil,
      now: try Self.instant("2026-10-03T03:00:00Z"),
      timeZone: tokyo,
      pickerTimeZone: losAngeles)

    #expect(presets.first?.id == "start")
    // 2 PM in Tokyo on October 5.
    #expect(presets.first?.date == (try Self.instant("2026-10-05T05:00:00Z")))
  }

  /// A time already past is not offered, and a time two presets share is
  /// offered once, under the first.
  @Test
  func presetsOfferOnlyTimesStillAheadAndEachTimeOnce() throws {
    let berlin = try Self.zone("Europe/Berlin")
    let presets = TaskDetailReminderPreset.presets(
      plannedDay: try Self.midnight(2026, 10, 2, in: berlin),
      plannedTime: 9 * 60..<10 * 60,
      dueDay: try Self.midnight(2026, 10, 1, in: berlin),
      now: try Self.instant("2026-10-01T10:00:00Z"),
      timeZone: berlin,
      pickerTimeZone: berlin)

    // The due day's 9 AM has passed; tomorrow's 9 AM is the start time.
    #expect(presets.map(\.id) == ["start", "hour"])
  }
}
