import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func loadOverview() async throws -> CoreBridgeOverview {
    let today = try await service.loadToday()
    let logicalDay: String
    if let capturedDay = today.logicalDay {
      logicalDay = capturedDay
    } else {
      logicalDay = try await service.getSessionContext().date
    }
    let currentFocus = try await service.loadCurrentFocus(date: logicalDay)
    return CoreBridgeOverview(
      localChangeSequence: today.localChangeSequence,
      currentFocus: currentFocus.map(Self.currentFocusValue(from:)),
      tasks: today.tasks.map { Self.taskValue(from: $0) }
    )
  }
}
