import Foundation

public enum CaptureTitleParser {
  public static func titles(from value: String) -> [String] {
    value
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}
