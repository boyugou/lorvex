import Foundation
import LorvexCore
import Testing

/// Durations and ages are worded by the system's CLDR rules in the locale
/// passed in, so each language gets its own units, plural forms, decimal
/// separator, and grammar. Every case names its locale, so the expectations
/// hold on any machine.
@Suite("Duration and age wording")
struct LorvexDurationFormatTests {
  private let english = Locale(identifier: "en_US")
  private let spanish = Locale(identifier: "es_ES")
  private let chinese = Locale(identifier: "zh-Hans_CN")
  private let russian = Locale(identifier: "ru_RU")

  @Test("Estimates read in minutes alone")
  func minutesAlone() {
    #expect(LorvexDurationFormat.minutes(45, locale: english) == "45 min")
    #expect(LorvexDurationFormat.minutes(90, locale: english) == "90 min")
    #expect(LorvexDurationFormat.minutes(90, locale: chinese) == "90分钟")
    #expect(LorvexDurationFormat.minutes(1, style: .spoken, locale: english) == "1 minute")
    #expect(LorvexDurationFormat.minutes(30, style: .spoken, locale: english) == "30 minutes")
    #expect(LorvexDurationFormat.minutes(30, style: .spoken, locale: spanish) == "30 minutos")
    #expect(LorvexDurationFormat.minutes(5, style: .spoken, locale: russian) == "5 минут")
    #expect(LorvexDurationFormat.minutes(-5, locale: english) == "0 min")
  }

  @Test("Lengths read in hours and minutes, leaving out a zero part")
  func hoursAndMinutes() {
    #expect(LorvexDurationFormat.hoursAndMinutes(45, locale: english) == "45 min")
    #expect(LorvexDurationFormat.hoursAndMinutes(120, locale: english) == "2 hr")
    #expect(LorvexDurationFormat.hoursAndMinutes(150, locale: english) == "2 hr 30 min")
    #expect(LorvexDurationFormat.hoursAndMinutes(150, locale: spanish) == "2 h 30 min")
    #expect(LorvexDurationFormat.hoursAndMinutes(150, locale: chinese) == "2小时30分钟")
    #expect(
      LorvexDurationFormat.hoursAndMinutes(90, style: .spoken, locale: english)
        == "1 hour, 30 minutes")
  }

  @Test("Rough totals read in hours with one decimal for a part hour")
  func hoursWithOneDecimal() {
    #expect(LorvexDurationFormat.hours(180, locale: english) == "3 hr")
    #expect(LorvexDurationFormat.hours(150, locale: english) == "2.5 hr")
    #expect(LorvexDurationFormat.hours(150, locale: spanish) == "2,5 h")
  }

  @Test("An age reads as time since then, in the language's own grammar")
  func elapsedAge() {
    #expect(LorvexDateFormatters.elapsed(seconds: 20, locale: english) == "1 min. ago")
    #expect(LorvexDateFormatters.elapsed(seconds: 5 * 60, locale: english) == "5 min. ago")
    #expect(LorvexDateFormatters.elapsed(seconds: 3 * 3_600 + 59, locale: english) == "3 hr. ago")
    #expect(LorvexDateFormatters.elapsed(seconds: 2 * 86_400, locale: english) == "2 days ago")
    #expect(LorvexDateFormatters.elapsed(seconds: 2 * 3_600, locale: spanish) == "hace 2 h")
    #expect(LorvexDateFormatters.elapsed(seconds: 3 * 86_400, locale: chinese) == "3天前")
    #expect(
      LorvexDateFormatters.elapsed(seconds: 3 * 86_400, locale: Locale(identifier: "de_DE"))
        == "vor 3 Tagen")
  }
}
