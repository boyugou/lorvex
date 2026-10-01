import LorvexCore
import Testing

/// Creates a task on Today's list and returns it. The task is planned for the
/// `yyyy-MM-dd` day `date`; Today's pool keeps a task planned for today or any
/// earlier day, so a fixed past date stays on the list whatever day the suite
/// runs.
@discardableResult
func seedWatchTodayTask(
  in service: any LorvexCoreServicing,
  date: String,
  title: String,
  priority: LorvexTask.Priority = .p2,
  estimatedMinutes: Int? = nil
) async throws -> LorvexTask {
  let created = try await service.createTask(
    TaskCreateDraft(title: title, priority: priority, estimatedMinutes: estimatedMinutes))
  return try await planTask(service, created.id, on: date)
}
