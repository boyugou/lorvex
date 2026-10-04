import Foundation

/// The user's own words in a sample dataset — task titles, notes, checklist
/// items, tags, list, habit, and event names, reviews, memory, and the
/// assistant's briefing — in one shipped language.
///
/// The sample datasets (the macOS `--ui-preview` seed, the iOS
/// `-lorvexSeedSampleData` seed, and the watch `-lorvexUIPreview` replica)
/// spell their content in English where they write it and pass each string
/// through the call operator, which returns the string's
/// translation into ``language``, or the English string itself when the
/// language has no table or the table has no entry for it. A capture run then
/// shows sample content in the interface language it launched in, which is
/// what a localized App Store screenshot needs, while a dataset seeded with
/// ``english`` (every test) stays exactly the English one.
///
/// Translations are keyed by the exact English string, so an English string
/// edited at its call site falls back to English until its table entry is
/// edited too. Names of people, products, and places are adapted to the
/// language rather than transliterated, as a speaker of it would write them.
/// The tables write digits as ASCII, and a translation comes back with its
/// digits in the numbering system its locale writes numbers in, so content
/// seeded under a locale that uses Arabic-Indic digits reads "٣٠" beside the
/// interface's own counts and times, as a person there would type it.
public struct LorvexSampleText: Sendable {
  /// The language the strings are translated into.
  public let language: AppLanguage

  /// The digits zero through nine as the locale writes numbers, or nil when
  /// it writes them in ASCII.
  private let digits: [Character]?

  /// A translator into `language` whose translations write their digits as
  /// `locale` writes numbers. The default is the locale the process runs in,
  /// so a capture launched with `-AppleLocale ar_SA` seeds "٣٠" and one
  /// launched with `-AppleLocale ar_AE` seeds "30", each matching the digits
  /// its interface formats.
  public init(language: AppLanguage, locale: Locale = .current) {
    self.language = language
    let digits = (0...9).compactMap { $0.formatted(.number.locale(locale).grouping(.never)).first }
    self.digits = digits.count == 10 && digits != Array("0123456789") ? digits : nil
  }

  /// The identity: every string comes back as written.
  public static let english = LorvexSampleText(language: .en)

  /// `english` in ``language``, or `english` when there is no translation.
  /// A translation's ASCII digits come back in the locale's numbering
  /// system; `english` itself always comes back as written.
  public func callAsFunction(_ english: String) -> String {
    guard let translation = Self.tables[language]?[english] else { return english }
    guard let digits else { return translation }
    return String(
      translation.map { character in
        guard character.isASCII, let value = character.wholeNumberValue else { return character }
        return digits[value]
      })
  }

  /// Each string of `english` translated as the single-string call
  /// translates it; for tags.
  public func callAsFunction(_ english: [String]) -> [String] {
    english.map { self($0) }
  }

  /// The translation tables, one per language that has one.
  static let tables: [AppLanguage: [String: String]] = [
    .ar: arabic,
    .es: spanish,
    .fa: persian,
    .fr: french,
    .he: hebrew,
    .hi: hindi,
    .it: italian,
    .ja: japanese,
    .ko: korean,
    .pl: polish,
    .ptBR: brazilianPortuguese,
    .ru: russian,
    .uk: ukrainian,
    .ur: urdu,
    .zhHans: simplifiedChinese,
    .zhHant: traditionalChinese,
  ]
}
