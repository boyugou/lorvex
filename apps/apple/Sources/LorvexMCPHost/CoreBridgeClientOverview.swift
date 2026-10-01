import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func loadOverview() async throws -> CoreBridgeOverview {
    let overview = try await service.loadOverviewTaskList()
    return CoreBridgeOverview(
      date: overview.logicalDay,
      localChangeSequence: overview.localChangeSequence,
      briefing: overview.briefing,
      today: overview.todayTasks.map { Self.taskValue(from: $0) },
      tasks: overview.tasks.map { Self.taskValue(from: $0) }
    )
  }
}
