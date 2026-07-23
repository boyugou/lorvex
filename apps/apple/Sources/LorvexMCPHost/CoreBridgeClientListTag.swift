import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func updateList(
    id: String,
    name: String?,
    description: String?,
    color: String?,
    icon: String?,
    aiNotes: String?
  ) async throws -> Value {
    Self.listValue(
      from: try await service.updateList(
        id: id, name: name, description: description, color: color, icon: icon, aiNotes: aiNotes))
  }

  func setListAINotes(id: String, notes: String) async throws -> Value {
    Self.listValue(from: try await service.setListAINotes(id: id, notes: notes))
  }

  func deleteList(id: String) async throws -> (deleted: Bool, previous: Value?) {
    let receipt = try await mcpMutations.deleteListForMcp(id: id)
    return (receipt.deleted, receipt.previous.map(Self.listValue(from:)))
  }

  func archiveList(id: String) async throws -> Value {
    Self.listValue(from: try await service.archiveList(id: id))
  }

  func unarchiveList(id: String) async throws -> Value {
    Self.listValue(from: try await service.unarchiveList(id: id))
  }

  func getList(id: String) async throws -> Value {
    Self.listValue(from: try await service.getList(id: id))
  }

  func getListHealthSnapshot() async throws -> Value {
    Self.listHealthValue(from: try await service.getListHealthSnapshot())
  }

  func listAllTags() async throws -> [String] {
    try await service.listAllTags()
  }

  func renameTag(oldName: String, newName: String) async throws {
    try await service.renameTag(oldTag: oldName, newTag: newName)
  }

  func deleteTag(name: String) async throws -> TagDeletionOutcome {
    try await service.deleteTag(name: name)
  }

  func mergeTags(source: String, target: String) async throws -> TagMergeOutcome {
    try await service.mergeTags(source: source, target: target)
  }

  func countTasksByTag(tag: String) async throws -> Int {
    try await service.countTasksByTag(tag: tag)
  }
}
