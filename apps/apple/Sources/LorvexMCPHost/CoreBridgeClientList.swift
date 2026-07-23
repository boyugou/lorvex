import Foundation
import LorvexCore
import LorvexDomain
import MCP

extension CoreBridgeClient {
  func loadLists() async throws -> [Value] {
    try await service.loadLists().lists.map(Self.listValue(from:))
  }

  func loadArchivedLists() async throws -> [Value] {
    try await service.loadArchivedLists().lists.map(Self.listValue(from:))
  }

  func createList(
    name: String, description: String?, color: String?, icon: String?, aiNotes: String?,
    originalID: String? = nil
  ) async throws -> Value {
    let normalized = (description?.isEmpty ?? true) ? nil : description
    // With an `original_id`, resolve collision-or-create and produce the rich
    // response under one writer transaction. A follow-up `getList` could race a
    // second process and return a value other than the candidate this call
    // committed.
    if let originalID {
      try Self.validateImportOriginalID(originalID, kind: .list)
      let candidate = ExportList(
        id: originalID, name: name, description: normalized, color: color, icon: icon,
        aiNotes: aiNotes)
      return Self.listValue(from: try await mcpMutations.createListForMcpIfAbsent(candidate))
    }
    return Self.listValue(
      from: try await service.createList(
        name: name, description: normalized, color: color, icon: icon, aiNotes: aiNotes))
  }

  func reorderLists(orderedIDs: [String]) async throws -> [Value] {
    try await service.reorderLists(orderedIDs: orderedIDs).lists.map(Self.listValue(from:))
  }
}
