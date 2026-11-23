import Foundation
import LorvexCore
import MCP

struct CoreBridgeOverview: Sendable {
  let date: String
  let localChangeSequence: Int
  let briefing: String?
  /// The day's list in Today's order.
  let today: [Value]
  /// The most important open tasks across the workspace that are not on
  /// ``today``.
  let tasks: [Value]
}

