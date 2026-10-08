import Foundation
import LorvexCore
import Testing

struct LorvexClockFormatTests {
  private let evening: Date = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 21, minute: 41))!
  }()

  private func label(_ format: LorvexClockFormat, _ identifier: String) -> String {
    LorvexDateFormatters.clockTime(
      evening, timeZone: .gmt, locale: format.applied(to: Locale(identifier: identifier)))
  }

  @Test func systemKeepsTheLocaleUnchanged() {
    let locale = Locale(identifier: "en_US")
    #expect(LorvexClockFormat.system.applied(to: locale) == locale)
    #expect(label(.system, "en_US") == "9:41\u{202F}PM")
    #expect(label(.system, "en_GB") == "21:41")
  }

  @Test func twentyFourHourOverridesATwelveHourRegion() {
    #expect(label(.twentyFourHour, "en_US") == "21:41")
  }

  @Test func twelveHourOverridesATwentyFourHourRegion() {
    #expect(label(.twelveHour, "en_GB").hasPrefix("9:41"))
    #expect(label(.twelveHour, "zh_Hans_CN") == "晚上9:41")
  }

  @Test func theOverrideKeepsTheLanguage() {
    let locale = LorvexClockFormat.twentyFourHour.applied(to: Locale(identifier: "zh_Hans_CN"))
    #expect(locale.language.languageCode == .chinese)
    #expect(locale.hourCycle == .zeroToTwentyThree)
  }

  @Test func hourLabelsAreTheSingleHourLabelOfEachHour() {
    let locale = Locale(identifier: "en_US")
    let labels = LorvexDateFormatters.hourLabels(timeZone: .gmt, locale: locale)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    #expect(labels.count == 24)
    #expect(Set(labels).count == 24)
    for hour in 0..<24 {
      let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: hour))!
      #expect(labels[hour] == LorvexDateFormatters.hourLabel(date, timeZone: .gmt, locale: locale))
    }
  }

  @Test func hourLabelsFollowTheClockFormat() {
    let region = Locale(identifier: "en_US")
    let twelve = LorvexDateFormatters.hourLabels(timeZone: .gmt, locale: region)
    let twentyFour = LorvexDateFormatters.hourLabels(
      timeZone: .gmt, locale: LorvexClockFormat.twentyFourHour.applied(to: region))
    #expect(twelve[21].contains("9") && twelve[21].contains("PM"))
    #expect(twentyFour[21] == "21")
    #expect(LorvexDateFormatters.hourLabels(timeZone: .gmt, locale: region) == twelve)
  }

  @Test func hourLabelsDoNotShiftWithTheTimeZone() {
    let locale = Locale(identifier: "en_US")
    let reference = LorvexDateFormatters.hourLabels(timeZone: .gmt, locale: locale)
    for identifier in ["Asia/Kolkata", "America/Los_Angeles", "Pacific/Kiritimati", "Pacific/Pago_Pago"] {
      let zone = TimeZone(identifier: identifier)!
      #expect(LorvexDateFormatters.hourLabels(timeZone: zone, locale: locale) == reference)
    }
  }
}
