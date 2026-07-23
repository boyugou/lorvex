import Foundation
import LorvexCore
import MCP

extension ToolRegistry {
  func tagNamesPayload() async throws -> [String] {
    try await coreBridge.listAllTags()
  }

  func renameTagPayload(oldName: String, newName: String) async throws -> Bool {
    try await coreBridge.renameTag(oldName: oldName, newName: newName)
    return true
  }

  func taskCountForTagPayload(tag: String) async throws -> Int {
    try await coreBridge.countTasksByTag(tag: tag)
  }

  func deleteTagPayload(name: String) async throws -> TagDeletionOutcome {
    try await coreBridge.deleteTag(name: name)
  }

  func mergeTagsPayload(source: String, target: String) async throws -> TagMergeOutcome {
    try await coreBridge.mergeTags(source: source, target: target)
  }
}
