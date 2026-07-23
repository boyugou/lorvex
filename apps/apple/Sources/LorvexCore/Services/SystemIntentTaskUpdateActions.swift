import Foundation
import LorvexDomain

extension LorvexSystemIntentRunner {
  public static func updateTask(
    id: LorvexTask.ID,
    title: String?,
    notes: String?,
    priority: Int?,
    estimatedMinutes: Int?,
    plannedDate: String?,
    tagsText: String?,
    dependsOnText: String?,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    let taskID = try validatedTaskID(id)
    let current = try await core.loadTask(id: taskID)
    return try await core.updateTask(
      id: taskID,
      title: try updatedTaskTitle(title, fallback: current.title),
      notes: updatedTaskText(notes, fallback: current.notes),
      priority: try parsedTaskPriority(priority, fallback: current.priority),
      estimatedMinutes: try parsedEstimatedMinutes(
        estimatedMinutes,
        fallback: current.estimatedMinutes
      ),
      plannedDate: try parsedOptionalIntentDate(plannedDate, fallback: current.dueDate),
      tags: parsedOptionalTextList(tagsText, fallback: current.tags),
      dependsOn: parsedOptionalTextList(dependsOnText, fallback: current.dependsOn)
    )
  }

  static func updatedTaskTitle(_ value: String?, fallback: String) throws -> String {
    guard let value else { return fallback }
    return try validatedTaskText(value, label: "title")
  }

  static func updatedTaskText(_ value: String?, fallback: String) -> String {
    guard let value else { return fallback }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func parsedTaskPriority(_ value: Int?, fallback: LorvexTask.Priority) throws
    -> LorvexTask.Priority
  {
    guard let value else { return fallback }
    switch value {
    case 1: return .p1
    case 2: return .p2
    case 3: return .p3
    default:
      throw LorvexCoreError.validation(
        field: "priority", message: "Task priority must be 1, 2, or 3.")
    }
  }

  static func parsedEstimatedMinutes(_ value: Int?, fallback: Int?) throws -> Int? {
    guard let value else { return fallback }
    guard (1...Int(ValidationLimits.maxEstimatedMinutes)).contains(value) else {
      throw LorvexCoreError.validation(
        field: "estimated_minutes",
        message: "Estimated minutes must be between 1 and 1,440.")
    }
    return value
  }
}
