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
}
