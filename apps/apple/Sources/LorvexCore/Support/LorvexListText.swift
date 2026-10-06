import Foundation

/// Reads the entries of a free-text list field: a task's tags, or the ids it
/// waits on.
public enum LorvexListText {
  /// The entries of `text`, split at commas, tabs, and line breaks, trimmed,
  /// without blanks or repeats, in the order they first appear.
  ///
  /// A line break is an LF, a CR LF, or a lone CR. Swift reads a CR LF pair as a
  /// single `Character` that `== "\n"` does not match, so the split asks each
  /// character whether it `isNewline`.
  public static func entries(in text: String) -> [String] {
    var seen = Set<String>()
    return text
      .split(whereSeparator: { $0 == "," || $0 == "\t" || $0.isNewline })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .filter { seen.insert($0).inserted }
  }
}
