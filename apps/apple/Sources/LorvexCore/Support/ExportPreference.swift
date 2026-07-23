import Foundation

/// Flat DTO for a single preference key/value pair in an export.
///
/// `value` is the JSON-encoded payload string as stored, mirroring
/// `PreferencesSnapshot.values`.
public struct ExportPreference: Codable, Sendable {
  public var key: String
  public var value: String

  public init(key: String, value: String) {
    self.key = key
    self.value = value
  }

  static let columns = ["key", "value"]
  var csvRow: [String] { [key, value] }
}
