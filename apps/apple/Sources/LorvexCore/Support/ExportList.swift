import Foundation

/// Flat DTO for a list row in an export.
public struct ExportList: Codable, Sendable {
  enum CodingKeys: String, CodingKey {
    case id
    case name
    case description
    case color
    case icon
    case aiNotes
    case archivedAt
    case position
  }

  public var id: String
  public var name: String
  /// List description. Omitted from the export when empty.
  public var description: String?
  /// Sidebar accent (#RRGGBB) and SF Symbol name. Optional; decode to `nil` when
  /// absent so the field is tolerant across export files. Carried so a list's
  /// visual identity survives an export→import round-trip.
  public var color: String?
  public var icon: String?
  /// AI-authored list scope/profile notes (optional; AI-only). Decodes to `nil`
  /// when absent so the field is forward/backward tolerant across export files.
  public var aiNotes: String?
  /// Soft-archive timestamp. `nil` means active.
  public var archivedAt: String?
  /// Synced manual display order. Required by the v1 backup wire.
  public var position: Int64

  public init(
    id: String, name: String, description: String? = nil,
    color: String? = nil, icon: String? = nil, aiNotes: String? = nil,
    archivedAt: String? = nil, position: Int64 = 0
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.color = color
    self.icon = icon
    self.aiNotes = aiNotes
    self.archivedAt = archivedAt
    self.position = position
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    color = try container.decodeIfPresent(String.self, forKey: .color)
    icon = try container.decodeIfPresent(String.self, forKey: .icon)
    aiNotes = try container.decodeIfPresent(String.self, forKey: .aiNotes)
    archivedAt = try container.decodeIfPresent(String.self, forKey: .archivedAt)
    position = try container.decode(Int64.self, forKey: .position)
  }

  public init(from list: LorvexList) {
    id = list.id
    name = list.name
    description = list.description.flatMap { $0.isEmpty ? nil : $0 }
    color = list.color
    icon = list.icon
    aiNotes = list.aiNotes
    archivedAt = list.archivedAt
    position = list.position
  }

  static let columns = [
    "id", "name", "description", "color", "icon", "ai_notes", "archived_at", "position",
  ]
  var csvRow: [String] {
    [
      id, name, description ?? "", color ?? "", icon ?? "", aiNotes ?? "", archivedAt ?? "",
      "\(position)",
    ]
  }
}
