import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func addTaskReminder(taskID: String, reminderAt: String) async throws -> Value {
    taskValue(try await service.addTaskReminder(taskID: taskID, reminderAt: reminderAt))
  }

  func removeTaskReminder(taskID: String, reminderID: String) async throws -> Value {
    taskValue(try await service.removeTaskReminder(taskID: taskID, reminderID: reminderID))
  }
}
