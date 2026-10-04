import Foundation
import LorvexCore
import Testing

/// A date that opens a title, heading, or label takes a capital where the
/// language capitalizes the start of a sentence, while the same date after
/// other words keeps the lowercase the language writes weekday and month names
/// in (Spanish, French, Italian, Portuguese, Russian, Ukrainian, Polish, Dutch,
/// and Romanian).
struct LorvexDateHeadingTests {
  private let utc = TimeZone(identifier: "UTC")!
  private static let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  /// The languages whose system data writes weekday and month names in lowercase.
  private static let lowercaseLanguages = [
    "es_ES", "fr_FR", "it_IT", "pt_BR", "ru_RU", "uk_UA", "pl_PL", "nl_NL", "ro_RO",
  ]

  /// Languages that already open with a capital, or have no letter case.
  private static let caselessOrCapitalized = [
    "en_US", "de_DE", "vi_VN", "id_ID", "ms_MY", "ja_JP", "zh_CN", "ko_KR", "ar_SA", "he_IL",
  ]

  private func day(_ key: String) throws -> Date {
    try #require(LorvexDateFormatters.ymdUTC.date(from: key))
  }

  @Test("A day line opens with a capital in a title and stays lowercase inside a sentence")
  func dayLineCapitalizesOnlyAtTheLeadingPosition() {
    let spanish = Locale(identifier: "es_ES")
    #expect(lorvexDayLine(logicalDay: "2026-09-22", position: .leading, locale: spanish) == "Martes, 22 de septiembre")
    #expect(lorvexDayLine(logicalDay: "2026-09-22", position: .inline, locale: spanish) == "martes, 22 de septiembre")
    #expect(lorvexDayLine(logicalDay: "2026-09-22", locale: spanish) == "martes, 22 de septiembre")

    for identifier in Self.lowercaseLanguages {
      let locale = Locale(identifier: identifier)
      let leading = lorvexDayLine(logicalDay: "2026-09-22", position: .leading, locale: locale)
      let inline = lorvexDayLine(logicalDay: "2026-09-22", position: .inline, locale: locale)
      #expect(leading.first?.isUppercase == true, "\(identifier): \(leading)")
      #expect(inline.first?.isLowercase == true, "\(identifier): \(inline)")
      #expect(leading.dropFirst() == inline.dropFirst(), "\(identifier)")
    }
    for identifier in Self.caselessOrCapitalized {
      let locale = Locale(identifier: identifier)
      #expect(
        lorvexDayLine(logicalDay: "2026-09-22", position: .leading, locale: locale)
          == lorvexDayLine(logicalDay: "2026-09-22", position: .inline, locale: locale),
        "\(identifier)")
    }
  }

  @Test("A short day line takes the same capital, and an unparsable day comes back unchanged")
  func shortDayLineCapitalizesToo() {
    let spanish = Locale(identifier: "es_ES")
    let leading = lorvexShortDayLine(logicalDay: "2026-09-22", position: .leading, locale: spanish)
    let inline = lorvexShortDayLine(logicalDay: "2026-09-22", position: .inline, locale: spanish)
    #expect(leading.first?.isUppercase == true, "\(leading)")
    #expect(inline.first?.isLowercase == true, "\(inline)")
    #expect(lorvexDayLine(logicalDay: "not a day", position: .leading) == "not a day")
    #expect(lorvexShortDayLine(logicalDay: "not a day", position: .leading) == "not a day")
  }

  @Test("A month title takes a capital at the leading position without sharing a formatter with the inline one")
  func monthTitleCapitalizes() throws {
    let date = try day("2026-09-22")
    let spanish = Locale(identifier: "es_ES")
    func title(_ position: LorvexDayPhrase.Position, _ locale: Locale) -> String {
      LorvexDateFormatters.string(date, template: "yMMMM", timeZone: utc, locale: locale, position: position)
    }
    // Inline, leading, inline again: each position keeps its own cached formatter.
    #expect(title(.inline, spanish) == "septiembre de 2026")
    #expect(title(.leading, spanish) == "Septiembre de 2026")
    #expect(title(.inline, spanish) == "septiembre de 2026")
    // Russian writes a narrow no-break space (U+202F) before the year suffix.
    #expect(title(.leading, Locale(identifier: "ru_RU")) == "Сентябрь 2026\u{202F}г.")
    #expect(title(.leading, Locale(identifier: "vi_VN")) == "Tháng 9 năm 2026")
    #expect(title(.leading, Locale(identifier: "en_US")) == "September 2026")
    #expect(title(.leading, Locale(identifier: "ja_JP")) == title(.inline, Locale(identifier: "ja_JP")))
  }

  @Test("A weekday heading takes a capital at the leading position")
  func weekdayHeadingCapitalizes() throws {
    let date = try day("2026-09-22")
    for identifier in Self.lowercaseLanguages {
      let locale = Locale(identifier: identifier)
      let leading = LorvexDateFormatters.string(
        date, template: "EEEE", timeZone: utc, locale: locale, position: .leading)
      #expect(leading.first?.isUppercase == true, "\(identifier): \(leading)")
    }
  }

  @Test("A range takes a capital at the leading position, by uppercasing its first letter")
  func rangeCapitalizes() throws {
    let start = try day("2026-10-02")
    let end = try day("2026-10-04")
    let spanish = Locale(identifier: "es_ES")
    let inline = LorvexDateFormatters.range(
      from: start, to: end, template: "EEEEMMMMd", timeZone: utc, locale: spanish)
    let leading = LorvexDateFormatters.range(
      from: start, to: end, template: "EEEEMMMMd", timeZone: utc, locale: spanish, position: .leading)
    #expect(inline.first?.isLowercase == true, "\(inline)")
    #expect(leading.first?.isUppercase == true, "\(leading)")
    #expect(leading.dropFirst() == inline.dropFirst())
  }

  /// Every call that writes a month title or a weekday heading from a template
  /// passes `position: .leading`: those texts stand alone as titles, headings,
  /// and labels. A new use inside a sentence belongs to the formatter's
  /// `.inline` default and is added to `inlineExceptions`.
  @Test("every month title and weekday heading template passes the leading position")
  func headingTemplatesPassTheLeadingPosition() throws {
    let templates = ["\"yMMMM\"", "\"EEEEMMMMd\"", "\"EEEE\""]
    let inlineExceptions: Set<String> = []
    let sources = Self.packageRoot.appending(path: "Sources")
    let files = try #require(
      FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    var checked = 0
    for case let url as URL in files where url.pathExtension == "swift" {
      let text = try String(contentsOf: url, encoding: .utf8)
      for template in templates {
        var cursor = text.startIndex
        while let range = text.range(of: "template: \(template)", range: cursor..<text.endIndex) {
          cursor = range.upperBound
          let window = text[range.lowerBound...].prefix(160)
          checked += 1
          let name = "\(url.lastPathComponent) \(template)"
          if inlineExceptions.contains(name) { continue }
          #expect(window.contains("position: .leading"), "\(name) is written without a leading position")
        }
      }
    }
    #expect(checked >= 6, "found only \(checked) heading templates")
  }

  @Test("the page titles, panel titles, and day choices pass the leading position")
  func titleSitesPassTheLeadingPosition() throws {
    let sites: [(path: String, needle: String)] = [
      ("Sources/LorvexMobile/MobileTodayCalmCopy.swift", "lorvexDayLine(logicalDay: logicalDay, position: .leading)"),
      ("Sources/LorvexApple/Views/TodayCalmCopy.swift", "lorvexDayLine(logicalDay: logicalDay, position: .leading)"),
      ("Sources/LorvexApple/Views/TodayCalmCopy.swift", "lorvexShortDayLine(logicalDay: logicalDay, position: .leading)"),
      ("Sources/LorvexApple/Views/MenuBarAgendaList.swift", "lorvexDayLine(logicalDay: key, position: .leading)"),
      ("Sources/LorvexApple/Views/TaskDetailMonthCalendar.swift", "capitalizationContext: .beginningOfSentence"),
      ("Sources/LorvexMobile/MobileTaskFieldEditor.swift", "capitalizationContext: .beginningOfSentence"),
    ]
    for site in sites {
      let source = try String(
        contentsOf: Self.packageRoot.appending(path: site.path), encoding: .utf8)
      #expect(source.contains(site.needle), "\(site.path): \(site.needle)")
    }
  }
}
