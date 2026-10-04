import Foundation
import LorvexCore
import Testing

/// The values the task-detail pickers offer on macOS and iPhone
/// (``LorvexTaskFieldChoices``): the time "Add Time" proposes, how a time
/// moves and ends, and the length and day choices.
@Suite("Task field choices")
struct LorvexTaskFieldChoicesTests {
  @Test("the length stepper buttons speak their sign and the spoken duration")
  func lengthStepButtonsSpeakTheirSignAndDuration() {
    let english = Locale(identifier: "en_US")
    #expect(LorvexTaskFieldChoices.lengthStepAccessibilityLabel(delta: 15, locale: english) == "+15 minutes")
    #expect(
      LorvexTaskFieldChoices.lengthStepAccessibilityLabel(delta: -15, locale: english)
        == "\u{2212}15 minutes")
  }

  @Test("Add Time on today starts at the next half hour, strictly after the clock")
  func newTimeOnTodayStartsAtTheNextHalfHour() {
    // 10:10 proposes 10:30; 10:30 itself proposes 11:00.
    #expect(LorvexTaskFieldChoices.newTime(length: 45, nowMinutes: 610, isToday: true) == 630..<675)
    #expect(LorvexTaskFieldChoices.newTime(length: nil, nowMinutes: 630, isToday: true) == 660..<690)
  }

  @Test("Add Time on another day, or with no clock, starts at 9:00")
  func newTimeOffTodayStartsAtNine() {
    #expect(LorvexTaskFieldChoices.newTime(length: 60, nowMinutes: 610, isToday: false) == 540..<600)
    #expect(LorvexTaskFieldChoices.newTime(length: nil, nowMinutes: nil, isToday: true) == 540..<570)
  }

  @Test("Add Time stays inside the day and keeps a usable length")
  func newTimeStaysInsideTheDay() {
    // 23:50 would propose midnight; the time is pulled back to end at midnight.
    #expect(LorvexTaskFieldChoices.newTime(length: nil, nowMinutes: 1430, isToday: true) == 1410..<1440)
    #expect(LorvexTaskFieldChoices.newTime(length: 0, nowMinutes: nil, isToday: false) == 540..<545)
    #expect(LorvexTaskFieldChoices.newTime(length: 2000, nowMinutes: nil, isToday: false) == 0..<1440)
  }

  @Test("moving the start keeps the length and the day")
  func movingTheStartKeepsTheLength() {
    #expect(LorvexTaskFieldChoices.time(600..<660, movingStartTo: 780) == 780..<840)
    #expect(LorvexTaskFieldChoices.time(600..<660, movingStartTo: 1420) == 1380..<1440)
    #expect(LorvexTaskFieldChoices.time(600..<660, movingStartTo: -30) == 0..<60)
  }

  @Test("setting the end: 0:00 is the midnight that closes the day; an early end becomes 15 minutes")
  func settingTheEnd() {
    #expect(LorvexTaskFieldChoices.time(600..<660, settingEndTo: 720) == 600..<720)
    #expect(LorvexTaskFieldChoices.time(600..<660, settingEndTo: 0) == 600..<1440)
    #expect(LorvexTaskFieldChoices.time(600..<660, settingEndTo: 590) == 600..<615)
    #expect(LorvexTaskFieldChoices.time(1430..<1440, settingEndTo: 1430) == 1430..<1440)
  }

  @Test("length text and the length ring")
  func lengthTextAndRing() {
    #expect(LorvexTaskFieldChoices.minutes(fromText: " 45 ") == 45)
    #expect(LorvexTaskFieldChoices.minutes(fromText: "soon") == 0)
    #expect(LorvexTaskFieldChoices.text(forMinutes: 30, locale: Locale(identifier: "en_US")) == "30")
    #expect(LorvexTaskFieldChoices.text(forMinutes: 30, locale: Locale(identifier: "ar_SA")) == "٣٠")
    #expect(LorvexTaskFieldChoices.text(forMinutes: 0) == "")
    // The Arabic number pad types Arabic-Indic digits.
    #expect(LorvexTaskFieldChoices.minutes(fromText: "٤٥") == 45)
    #expect(LorvexTaskFieldChoices.lengthFraction(60) == 0.5)
    #expect(LorvexTaskFieldChoices.lengthFraction(-5) == 0)
    #expect(LorvexTaskFieldChoices.lengthFraction(500) == 1)
  }

  @Test("the quick days are today and the next two, as local midnights")
  func quickDays() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let now = try #require(ISO8601DateFormatter().date(from: "2026-09-29T15:00:00Z"))

    let days = LorvexTaskFieldChoices.quickDays(from: now, calendar: calendar)

    #expect(days.map(\.offset) == [0, 1, 2])
    #expect(
      days.map { ISO8601DateFormatter().string(from: $0.date) }
        == ["2026-09-29T00:00:00Z", "2026-09-30T00:00:00Z", "2026-10-01T00:00:00Z"])
  }

  @Test("day presets name the coming weekend, the next Monday, and next month")
  func dayPresets() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    calendar.firstWeekday = 2
    let formatter = ISO8601DateFormatter()
    func day(_ preset: LorvexTaskFieldChoices.DayPreset, _ now: String) throws -> String? {
      let date = try #require(formatter.date(from: now))
      return LorvexTaskFieldChoices.date(for: preset, from: date, calendar: calendar).map {
        String(formatter.string(from: $0).prefix(10))
      }
    }

    // 2026-09-30 is a Wednesday.
    #expect(try day(.today, "2026-09-30T15:00:00Z") == "2026-09-30")
    #expect(try day(.tomorrow, "2026-09-30T15:00:00Z") == "2026-10-01")
    #expect(try day(.thisWeekend, "2026-09-30T15:00:00Z") == "2026-10-03")
    #expect(try day(.nextMonday, "2026-09-30T15:00:00Z") == "2026-10-05")
    #expect(try day(.nextMonth, "2026-09-30T15:00:00Z") == "2026-10-01")
    // On a weekend there is no "this weekend"; a Monday's next Monday is a week out.
    #expect(try day(.thisWeekend, "2026-10-03T15:00:00Z") == nil)
    #expect(try day(.thisWeekend, "2026-10-04T15:00:00Z") == nil)
    #expect(try day(.nextMonday, "2026-10-04T15:00:00Z") == "2026-10-05")
    #expect(try day(.nextMonday, "2026-10-05T15:00:00Z") == "2026-10-12")
    #expect(try day(.nextMonth, "2026-12-15T15:00:00Z") == "2027-01-01")
  }
}
