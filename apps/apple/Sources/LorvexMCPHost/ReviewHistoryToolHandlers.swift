import Foundation
import MCP

extension ToolRegistry {
  func reviewHistoryResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let payload = try await coreBridge.loadReviewHistory(arguments: arguments)
    let count = payload.objectValue?["returned"]?.intValue ?? 0

    return CallTool.Result(
      content: [
        .text(
          text: "Returned \(count) review(s).", annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(payload),
      isError: false
    )
  }
}
