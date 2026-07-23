import Foundation
import LorvexCore
import MCP

struct CoreBridgeOverview: Sendable {
  let localChangeSequence: Int
  let currentFocus: Value?
  let tasks: [Value]
}

