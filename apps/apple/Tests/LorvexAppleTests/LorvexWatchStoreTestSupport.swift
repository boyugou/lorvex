import LorvexCore
import Testing

func makeWatchFocusPlan(date: String, taskIDs: [String]) -> CurrentFocusPlan {
  CurrentFocusPlan(
    date: date,
    taskIDs: taskIDs,
    briefing: nil,
    timezone: "UTC",
    localChangeSequence: 1
  )
}

@discardableResult
func seedWatchFocus(
  in service: SwiftLorvexCoreService,
  date: String,
  title: String,
  estimatedMinutes: Int? = nil
) async throws -> LorvexTask {
  let created = try await service.createTask(title: title, notes: "")
  let task = try await service.updateTask(
    id: created.id,
    title: created.title,
    notes: created.notes,
    priority: created.priority,
    estimatedMinutes: estimatedMinutes,
    plannedDate: created.dueDate,
    tags: created.tags,
    dependsOn: created.dependsOn
  )
  _ = try await service.setCurrentFocus(
    date: date,
    taskIDs: [task.id],
    briefing: nil,
    timezone: "UTC"
  )
  return task
}
