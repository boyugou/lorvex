import Foundation
import Testing

@testable import LorvexCore

@Suite("Single final period")
struct LorvexFinalPeriodTests {
  @Test("an abbreviation's period doubles as the sentence's full stop")
  func abbreviationPeriodIsKept() {
    #expect(
      lorvexSingleFinalPeriod("Jeśli przeniesiesz „Raport” na jutro, zwolnisz około 11 godz..")
        == "Jeśli przeniesiesz „Raport” na jutro, zwolnisz około 11 godz.")
    #expect(lorvexSingleFinalPeriod("Último envio: há 5 min..") == "Último envio: há 5 min.")
    #expect(
      lorvexSingleFinalPeriod("Tu horario del día termina: 5:00 p.m..")
        == "Tu horario del día termina: 5:00 p.m.")
  }

  @Test("text with one final period, none, or another mark is unchanged")
  func otherEndingsAreUnchanged() {
    for text in ["Done.", "Done", "Done!", "Done…", "完了。", "Готово ", "", "."] {
      #expect(lorvexSingleFinalPeriod(text) == text)
    }
  }

  @Test("an ellipsis of three or more dots is never shortened")
  func ellipsisStaysWhole() {
    for text in ["Wait...", "Wait....", "Wait....."] {
      #expect(lorvexSingleFinalPeriod(text) == text)
    }
  }

  @Test("two periods that are the whole text collapse to one")
  func bareDoublePeriod() {
    #expect(lorvexSingleFinalPeriod("..") == ".")
  }

  /// A sentence template ends in its own full stop after a formatted value. In
  /// every shipped language the system's duration and relative-time phrases,
  /// completed that way, end in exactly one period.
  @Test("a duration or an elapsed time at a sentence's end leaves one period in every shipped language")
  func shippedLanguagesEndInOnePeriod() {
    let reference = Date(timeIntervalSince1970: 0)
    var sawAbbreviationPeriod = false
    for language in AppLanguage.selectable {
      let locale = Locale(identifier: language.rawValue)
      var values = [5, 45, 60, 75, 120, 660].map {
        LorvexDurationFormat.hoursAndMinutes($0, locale: locale)
      }
      let relative = RelativeDateTimeFormatter()
      relative.locale = locale
      relative.unitsStyle = .short
      relative.dateTimeStyle = .numeric
      let ages: [TimeInterval] = [-300, -3 * 3_600, -3 * 86_400, -14 * 86_400]
      for age in ages {
        values.append(
          relative.localizedString(for: reference.addingTimeInterval(age), relativeTo: reference))
      }
      for value in values {
        let sentence = lorvexSingleFinalPeriod("\(value).")
        #expect(sentence == (value.hasSuffix(".") ? value : value + "."), "\(language.rawValue): \(value)")
        sawAbbreviationPeriod = sawAbbreviationPeriod || value.hasSuffix(".")
      }
    }
    #expect(sawAbbreviationPeriod, "no shipped language wrote an abbreviation period; the sample proves nothing")
  }
}

/// The Today sentences that end on a formatted value, and the sync summary's
/// last push, pass through ``lorvexSingleFinalPeriod(_:)``. The sentences are
/// built from catalog text in the app's language, which a test cannot switch,
/// so the wiring is pinned in the source.
@Suite("Final period wiring")
struct LorvexFinalPeriodWiringTests {
  private var packageRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func uses(_ path: String) throws -> Int {
    let source = try String(contentsOf: packageRoot.appending(path: path), encoding: .utf8)
    return source.components(separatedBy: "lorvexSingleFinalPeriod(").count - 1
  }

  @Test("the overbooked reason and the no-time caption close with one period on both platforms")
  func todayCopyCollapsesTheFinalPeriod() throws {
    #expect(try uses("Sources/LorvexApple/Views/TodayCalmCopy.swift") == 2)
    #expect(try uses("Sources/LorvexMobile/MobileTodayCalmCopy.swift") == 2)
  }

  @Test("the sync summary's last push closes with one period")
  func syncSummaryCollapsesTheFinalPeriod() throws {
    #expect(try uses("Sources/LorvexApple/Views/SettingsCloudSyncLocalization.swift") == 1)
  }
}
