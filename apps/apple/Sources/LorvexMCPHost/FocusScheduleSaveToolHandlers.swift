import Foundation
import LorvexDomain
import MCP

extension ToolRegistry {
  func saveFocusScheduleResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let date = arguments["date"]?.stringValue, !date.isEmpty else {
      return Self.errorResult(
        code: "validation",
        message: "A date value is required.",
        toolName: "save_focus_schedule"
      )
    }
    if let blocksValue = arguments["blocks"], !blocksValue.isNull, blocksValue.arrayValue == nil {
      throw ValidationError.invalidFormat(
        field: "blocks", expected: "an array of block objects",
        actual: StrictArgumentArray.describe(blocksValue))
    }
    let blocks = arguments["blocks"]?.arrayValue ?? []
    guard !blocks.isEmpty else {
      return Self.errorResult(
        code: "validation",
        message: "A non-empty blocks array is required.",
        toolName: "save_focus_schedule"
      )
    }
    let schedule = try await saveFocusSchedulePayload(
      date: date,
      blocks: blocks,
      rationale: try StrictScalarArguments.optionalString(
        arguments["rationale"], field: "rationale")
    )
    return successResult(text: "Saved focus schedule for \(date)", value: schedule)
  }
}
