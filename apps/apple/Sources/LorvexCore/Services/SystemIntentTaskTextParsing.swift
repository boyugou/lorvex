import Foundation

extension LorvexSystemIntentRunner {
  static func parsedOptionalIntentDate(_ value: String?, fallback: Date?) throws -> Date? {
    guard let value else { return fallback }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return try parsedIntentDate(trimmed)
  }

  static func parsedOptionalTextList(_ value: String?, fallback: [String]) -> [String] {
    guard let value else { return fallback }
    return value
      .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " })
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}
