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
public struct LorvexSampleText: Sendable {
  /// The language the strings are translated into.
  public let language: AppLanguage

  public init(language: AppLanguage) {
    self.language = language
  }

  /// The identity: every string comes back as written.
  public static let english = LorvexSampleText(language: .en)

  /// `english` in ``language``, or `english` when there is no translation.
  public func callAsFunction(_ english: String) -> String {
    Self.tables[language]?[english] ?? english
  }

  /// Each string of `english` translated as the single-string call
  /// translates it; for tags.
  public func callAsFunction(_ english: [String]) -> [String] {
    english.map { self($0) }
  }

  /// The translation tables, one per language that has one.
  static let tables: [AppLanguage: [String: String]] = [
    .zhHans: simplifiedChinese
  ]
}
