import Foundation

extension LorvexCaptureVocabulary {
  // The day-first numeric dates the Indic-script vocabularies (Marathi,
  // Bengali, Telugu, and Tamil) share. A vocabulary reads its line with its
  // native digits as ASCII digits before these patterns see it.

  /// "15.10.2026", "15/10/2026", "15-10-2026": a day, a month, and a four-digit
  /// year, with no digit, dot, comma, colon, slash, or hyphen touching either
  /// side, as a pattern without groups. A date written like this is a date
  /// wherever it stands.
  static let numericDateWithYear =
    #"(?<![\p{N}.,:/-])\d{1,2}[./-]\d{1,2}[./-](?:19|20)\d{2}(?![\p{N}]|[.,/:-]\p{N})"#

  /// "15/10", "15-10", "15.10", "15.10.": a day and a month with no year, as a
  /// pattern without groups. A pair of numbers like this is as often a time, a
  /// score, a fraction, or a range ("5.30", "3-4", "1/2"), so a vocabulary reads
  /// it only where a word of its own introduces or ends it.
  static let numericDateWithoutYear =
    #"(?<![\p{N}.,:/-])\d{1,2}[./-]\d{1,2}\.?(?![\p{N}]|[.,/:-]\p{N})"#

  /// The date a matched numeric date names, in digits: "15.10.2026", "15/10",
  /// "15-10-2026", "15.10.". Nil when the month is not 1 to 12 or the day is not
  /// 1 to 31, so a pair such as "5.30" names no date.
  static func numericDate(_ text: String) -> ExplicitDate? {
    guard let found = text.firstMatch(of: /(\d{1,2})[.\/-](\d{1,2})(?:[.\/-]((?:19|20)\d{2}))?/),
      let day = number(found.output.1), let month = number(found.output.2),
      (1...31).contains(day), (1...12).contains(month)
    else { return nil }
    return ExplicitDate(year: found.output.3.flatMap { number($0) }, month: month, day: day)
  }
}
