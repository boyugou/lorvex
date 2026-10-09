import Foundation
import LorvexDomain
import MCP

extension ToolRegistry {
  /// The per-day targets `create_habit` and `update_habit` accept.
  static let habitTargetCountRange = 1...Int(ValidationLimits.maxHabitTargetCount)

  static var habitTargetCountMessage: String {
    "target_count must be between 1 and \(ValidationLimits.maxHabitTargetCount)."
  }

  func createHabitResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard
      let name = arguments["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      !name.isEmpty
    else {
      return Self.errorResult(code: "validation", message: "A non-empty habit name is required.", toolName: "create_habit")
    }
    let cue = try StrictScalarArguments.optionalString(arguments["cue"], field: "cue")
    let icon = try StrictScalarArguments.optionalString(arguments["icon"], field: "icon")
    let color = try StrictScalarArguments.optionalString(arguments["color"], field: "color")
    // Reject a target_count outside the range rather than silently clamping,
    // matching update_habit.
    let targetCount = try StrictScalarArguments.int(
      arguments["target_count"], field: "target_count", default: 1)
    if !Self.habitTargetCountRange.contains(targetCount) {
      return Self.errorResult(
        code: "validation", message: Self.habitTargetCountMessage, toolName: "create_habit")
    }
    let frequencyType = try StrictScalarArguments.string(
      arguments["frequency_type"], field: "frequency_type", default: "daily")
    let cadence = try CoreBridgeClient.habitCadenceInput(
      frequencyType: frequencyType, arguments: arguments)
    let milestoneTarget = try StrictScalarArguments.optionalInt(
      arguments["milestone_target"], field: "milestone_target")

    let habit = try await coreBridge.createHabit(
      name: name, cue: cue, icon: icon, color: color, targetCount: targetCount,
      cadence: cadence, milestoneTarget: milestoneTarget,
      originalID: try CoreBridgeClient.strictImportOriginalID(
        arguments["original_id"], field: "original_id"))
    return successResult(text: "Created habit: \(name)", value: habit)
  }
}
