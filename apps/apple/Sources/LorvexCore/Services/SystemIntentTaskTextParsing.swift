import Foundation
import LorvexDomain

extension LorvexSystemIntentRunner {
  /// The planned-day patch for an optional `yyyy-MM-dd` argument: nil leaves
  /// the day, a blank value clears it, and a date sets it.
  static func plannedDatePatch(_ value: String?) throws -> Patch<Date> {
    guard let value else { return .unset }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .clear }
    return .set(try parsedIntentDate(trimmed))
  }

  /// The entries of a comma-, space-, or line-separated list, without blanks.
  /// A line break is an LF, a CR LF, or a lone CR; a CR LF pair is one
  /// `Character` that `== "\n"` misses, so the split asks `isNewline`.
  static func parsedTextList(_ value: String) -> [String] {
    value
      .split(whereSeparator: { $0 == "," || $0 == " " || $0.isNewline })
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}
