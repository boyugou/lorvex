import Foundation
import LorvexCore
import MCP

/// Maps the `LorvexCore` list model types onto the MCP `Value` JSON shapes the
/// list tool handlers return. Field names and shapes mirror the contract
/// expected by existing MCP clients, so external integrations see stable
/// objects while the implementation stays pure Swift.
extension CoreBridgeClient {
  static func listValue(from list: LorvexList) -> Value {
    .object([
      "id": .string(list.id),
      "name": .string(list.name),
      "description": list.description.map(Value.string) ?? .null,
      "ai_notes": list.aiNotes.map(Value.string) ?? .null,
      "icon": list.icon.map(Value.string) ?? .null,
      "color": list.color.map(Value.string) ?? .null,
      "open_count": .int(list.openCount),
      "total_count": .int(list.totalCount),
      "archived": .bool(list.isArchived),
      "updated_at": .string(list.updatedAt),
    ])
  }

  static func listHealthValue(from snapshot: ListHealthSnapshot) -> Value {
    .object([
      "date": .string(snapshot.date),
      "total_lists": .int(snapshot.totalLists),
      "lists": .array(
        snapshot.lists.map { entry in
          .object([
            "id": .string(entry.id),
            "name": .string(entry.name),
            "color": entry.color.map(Value.string) ?? .null,
            "icon": entry.icon.map(Value.string) ?? .null,
            "open_count": .int(entry.openCount),
            "overdue_open_count": .int(entry.overdueOpenCount),
            "due_today_open_count": .int(entry.dueTodayOpenCount),
          ])
        }),
    ])
  }
}
