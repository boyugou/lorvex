import Foundation

/// Numbers a person types, read in the digits of any script.
///
/// A keyboard types the digits of its own script: the Arabic number pad types
/// "٤٥", a Persian one "۴۵", a Devanagari one "४५", and a Chinese or Japanese
/// input method often "４５" in full width. `Int(_:)` and `Double(_:)` read only
/// ASCII digits, so every place that turns typed text into a number (a field's
/// draft, a quick-add token) reads it through this type instead, and a field
/// shows its starting number in the user's locale through ``text(for:locale:)``.
public enum LorvexNumberInput {
  /// The whole number `text` spells, or nil when it spells none.
  ///
  /// Accepts decimal digits from any script, mixed freely, with an optional
  /// leading `+` or `-` and surrounding whitespace, and ignores invisible
  /// formatting marks such as the bidirectional marks a right-to-left paste
  /// carries. Rejects grouping separators, decimal points, and numerals that
  /// are not decimal digits (fractions, Roman numerals, CJK numerals), and
  /// values beyond `Int`.
  public static func integer(from text: some StringProtocol) -> Int? {
    Int(asciiDigits(text))
  }

  /// The number `text` spells, with an optional ASCII `.` decimal point, or
  /// nil when it spells none. Digits and marks read as in
  /// ``integer(from:)``.
  public static func decimal(from text: some StringProtocol) -> Double? {
    let ascii = asciiDigits(text)
    // `Double(_:)` also reads "nan", "inf", and hexadecimal floats; typed
    // amounts are only digits, a sign, and a decimal point.
    guard ascii.allSatisfy({ $0.isASCII && ($0.isNumber || "+-.".contains($0)) }) else { return nil }
    return Double(ascii)
  }

  /// The text a number field starts with for `value`: the value in `locale`'s
  /// digits without grouping ("1440", "١٤٤٠" for Arabic (Saudi Arabia)),
  /// which ``integer(from:)`` reads back.
  public static func text(for value: Int, locale: Locale = .autoupdatingCurrent) -> String {
    value.formatted(.number.grouping(.never).locale(locale))
  }

  /// `text` trimmed of whitespace and formatting marks, with every decimal
  /// digit replaced by its ASCII digit and everything else kept, so `Int(_:)`
  /// or `Double(_:)` decides what remains.
  private static func asciiDigits(_ text: some StringProtocol) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in text.unicodeScalars where scalar.properties.generalCategory != .format {
      if scalar.properties.numericType == .decimal, let value = scalar.properties.numericValue {
        scalars.append(Unicode.Scalar(UInt8(ascii: "0") + UInt8(value)))
      } else {
        scalars.append(scalar)
      }
    }
    return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
