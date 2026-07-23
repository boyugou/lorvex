import Foundation

extension String {
  /// Trims leading/trailing whitespace and newlines; `nil` when the trimmed
  /// result is empty, else the trimmed value. The canonical "a blank
  /// submission means no value" normalization for optional free-text fields
  /// (notes, location, timezone, review entries, …) shared by the MCP host,
  /// System Intents, and the on-disk core service.
  public var trimmedNilIfEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

extension Optional where Wrapped == String {
  /// `nil` when the receiver is `nil` or trims to an empty string, else the
  /// trimmed value. Lets an already-optional field normalize without an
  /// extra `?` at the call site (`value.trimmedNilIfEmpty` rather than
  /// `value?.trimmedNilIfEmpty`).
  public var trimmedNilIfEmpty: String? {
    self?.trimmedNilIfEmpty
  }
}
