import Foundation
import LorvexCore
import MCP

extension ToolRegistry {
  func listsPayload(includeArchived: Bool = false) async throws -> [Value] {
    let active = try await coreBridge.loadLists()
    guard includeArchived else { return active }
    return active + (try await coreBridge.loadArchivedLists())
  }

  func createListPayload(
    name: String, description: String?, color: String?, icon: String?, aiNotes: String?,
    originalID: String? = nil
  ) async throws -> Value {
    try await coreBridge.createList(
      name: name, description: description, color: color, icon: icon, aiNotes: aiNotes,
      originalID: originalID)
  }

  func updateListPayload(
    id: String,
    name: String?,
    description: String?,
    color: String?,
    icon: String?,
    aiNotes: String?
  ) async throws -> Value {
    try await coreBridge.updateList(
      id: id,
      name: name,
      description: description,
      color: color,
      icon: icon,
      aiNotes: aiNotes
    )
  }

  func setListAINotesPayload(id: String, notes: String) async throws -> Value {
    try await coreBridge.setListAINotes(id: id, notes: notes)
  }

  func archiveListPayload(id: String) async throws -> Value {
    try await coreBridge.archiveList(id: id)
  }

  func unarchiveListPayload(id: String) async throws -> Value {
    try await coreBridge.unarchiveList(id: id)
  }

  func deleteListPayload(id: String) async throws -> Value {
    let receipt = try await coreBridge.deleteList(id: id)
    return deletedListPayload(id: id, previous: receipt.previous)
  }

  func listPayload(id: String) async throws -> Value {
    try await coreBridge.getList(id: id)
  }

  func listHealthSnapshotPayload() async throws -> Value {
    try await coreBridge.getListHealthSnapshot()
  }

  func reorderListsPayload(orderedIDs: [String]) async throws -> [Value] {
    try await coreBridge.reorderLists(orderedIDs: orderedIDs)
  }

  private func deletedListPayload(id: String, previous: Value?) -> Value {
    .object([
      // `previous == nil` means the id did not exist, so the core delete was a
      // no-op — report `deleted: false` rather than a spurious success.
      "deleted": .bool(previous != nil),
      "id": .string(id),
      "previous": previous ?? .null,
    ])
  }
}
