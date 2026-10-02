import Foundation
import LorvexDomain

extension LorvexSystemIntentRunner {
  /// Write the fields a Siri or Shortcuts update supplies and leave every
  /// other field as stored.
  ///
  /// A nil argument leaves its field alone; a blank planned date clears the
  /// planned day, a blank tag list or an empty dependency list clears that
  /// list, and a blank title is refused as ``LorvexCoreError/emptyTitle``.
  /// `dependsOn` replaces the task's dependencies with those task IDs. The
  /// write is one ``TaskUpdateDraft`` patch, so fields this action has no
  /// parameter for — the deadline, the hide-until date, the time on an
  /// unchanged planned day — are never rewritten from an earlier read. Moving
  /// the task to another planned day clears its time, as every planned-day
  /// move does.
  public static func updateTask(
    id: LorvexTask.ID,
    title: String?,
    notes: String?,
    priority: Int?,
    estimatedMinutes: Int?,
    plannedDate: String?,
    tagsText: String?,
    dependsOn: [LorvexTask.ID]?,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    let taskID = try validatedTaskID(id)
    return try await core.updateTask(
      TaskUpdateDraft(
        id: taskID,
        title: title.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
        notes: notes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
        priority: try priority.map(parsedTaskPriority),
        estimatedMinutes: try estimatedMinutes.map { .set(try validatedEstimatedMinutes($0)) }
          ?? .unset,
        plannedDate: try plannedDatePatch(plannedDate),
        tags: tagsText.map(parsedTextList),
        dependsOn: dependsOn.map { ids in
          ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }))
  }

  static func parsedTaskPriority(_ value: Int) throws -> LorvexTask.Priority {
    switch value {
    case 1: return .p1
    case 2: return .p2
    case 3: return .p3
    default:
      throw LorvexCoreError.validation(
        field: "priority", message: "Task priority must be 1, 2, or 3.")
    }
  }

  static func validatedEstimatedMinutes(_ value: Int) throws -> Int {
    guard (1...Int(ValidationLimits.maxEstimatedMinutes)).contains(value) else {
      throw LorvexCoreError.validation(
        field: "estimated_minutes",
        message: "Estimated minutes must be between 1 and 1,440.")
    }
    return value
  }
}
