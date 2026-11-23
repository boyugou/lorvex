import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func loadOverview() async throws -> CoreBridgeOverview {
    let overview = try await service.loadOverviewTaskList()
    // The day's list is read whole, and most rows fill a third of their
    // fields, so a row carries the fields that have a value.
    let rows = TaskValueOptions.filled
    return CoreBridgeOverview(
      date: overview.logicalDay,
      localChangeSequence: overview.localChangeSequence,
      briefing: overview.briefing,
      today: overview.todayTasks.map { Self.taskValue(from: $0, options: rows) },
      tasks: overview.tasks.map { Self.taskValue(from: $0, options: rows) }
    )
  }
}
