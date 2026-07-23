import Foundation

public struct ExportTag: Codable, Equatable, Sendable {
  public var id: String
  public var displayName: String
  public var color: String?
  public var createdAt: String?
  public var updatedAt: String?

  public init(
    id: String,
    displayName: String,
    color: String? = nil,
    createdAt: String? = nil,
    updatedAt: String? = nil
  ) {
    self.id = id
    self.displayName = displayName
    self.color = color
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public static let columns = ["id", "displayName", "color", "createdAt", "updatedAt"]

  public var csvRow: [String] {
    [id, displayName, color ?? "", createdAt ?? "", updatedAt ?? ""]
  }
}
