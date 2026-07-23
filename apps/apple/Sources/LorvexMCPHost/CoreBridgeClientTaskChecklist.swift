import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func addTaskChecklistItem(taskID: String, text: String) async throws -> Value {
    taskValue(try await service.addTaskChecklistItem(taskID: taskID, text: text))
  }

  func toggleTaskChecklistItem(itemID: String, completed: Bool) async throws -> Value {
    taskValue(try await service.toggleTaskChecklistItem(itemID: itemID, completed: completed))
  }

  func updateTaskChecklistItem(itemID: String, text: String) async throws -> Value {
    taskValue(try await service.updateTaskChecklistItem(itemID: itemID, text: text))
  }

  func removeTaskChecklistItem(itemID: String) async throws -> Value {
    taskValue(try await service.removeTaskChecklistItem(itemID: itemID))
  }

  func reorderTaskChecklistItems(taskID: String, itemIDs: [String]) async throws -> Value {
    taskValue(try await service.reorderTaskChecklistItems(taskID: taskID, itemIDs: itemIDs))
  }
}
