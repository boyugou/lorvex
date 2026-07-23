import Foundation

/// Flat DTO for a memory entry row in an export.
public struct ExportMemoryEntry: Codable, Sendable {
  public var id: String?
  public var key: String
  public var content: String
  public var updatedAt: String

  public init(
    id: String? = nil,
    key: String,
    content: String,
    updatedAt: String
  ) {
    self.id = id
    self.key = key
    self.content = content
    self.updatedAt = updatedAt
  }

  static let columns = ["id", "key", "content", "updatedAt"]
  var csvRow: [String] {
    [id ?? "", key, content, updatedAt]
  }
}
