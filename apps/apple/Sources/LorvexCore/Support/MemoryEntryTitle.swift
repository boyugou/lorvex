import Foundation

extension MemoryEntry {
  /// The entry's name as a person reads it.
  ///
  /// A key is the handle the assistant and the MCP tools address an entry by
  /// (`user_profile`, `pending_followups`), so every surface that names an
  /// entry shows this title and only the editor's key field shows the handle.
  /// The title joins the key's words (split on `_`, `-`, and whitespace) with
  /// single spaces and capitalizes the first letter: `user_profile` reads
  /// "User profile". A word the product spells as an initialism or a platform
  /// name (`ai`, `mcp`, `ios`, …) keeps that spelling, a word with capitals of
  /// its own (`SwiftUI`) is left alone, and a key typed as a phrase ("coffee
  /// order") reads as typed with its first letter capitalized, in the user's
  /// language (Turkish capitalizes "i" as "İ"). A key with no words at all is
  /// returned unchanged.
  public var displayTitle: String { Self.displayTitle(forKey: key) }

  /// ``displayTitle`` for a bare key, for callers that hold only the key.
  /// `locale` decides how the first letter is capitalized.
  public static func displayTitle(forKey key: String, locale: Locale = .current) -> String {
    let parts = key.split { $0 == "_" || $0 == "-" || $0.isWhitespace }
    guard let first = parts.first else { return key }
    var words = parts.map { part in spelledWords[part.lowercased()] ?? String(part) }
    if spelledWords[first.lowercased()] == nil {
      words[0] = words[0].prefix(1).uppercased(with: locale) + String(words[0].dropFirst())
    }
    return words.joined(separator: " ")
  }

  /// Words that read wrong in sentence case: the product's initialisms and the
  /// platform names Apple spells with their own capitals.
  private static let spelledWords: [String: String] = [
    "ai": "AI", "api": "API", "id": "ID", "mcp": "MCP", "ui": "UI", "url": "URL",
    "carplay": "CarPlay", "ios": "iOS", "ipad": "iPad", "ipados": "iPadOS",
    "iphone": "iPhone", "macos": "macOS", "watchos": "watchOS",
  ]
}
