import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func setDailyBriefing(date: String, briefing: String) async throws -> Value {
    let receipt = try await mcpMutations.setDailyBriefingForMcp(date: date, briefing: briefing)
    return .object([
      "date": .string(receipt.date),
      "briefing": receipt.briefing.map(Value.string) ?? .null,
      "previous": .object(["briefing": receipt.previous.map(Value.string) ?? .null]),
      "changed": .bool(receipt.changed),
    ])
  }
}
