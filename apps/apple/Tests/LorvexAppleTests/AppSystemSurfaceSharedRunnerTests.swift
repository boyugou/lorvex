import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func sharedSystemIntentRunnerMutatesTasksWithoutAppleAppTargetState() async throws {
  let core = try await makeSeededInMemoryCore()
  let createdTitle = try await LorvexSystemIntentRunner.captureTask(
    title: "  Shared system intent task  ",
    notes: "Created through LorvexCore.",
    core: core
  )
  let openAfterCapture = try await core.listTasks(
    status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  let created = try #require(
    openAfterCapture.tasks.first { $0.title == "Shared system intent task" })
  #expect(createdTitle == "Shared system intent task")
  #expect(created.notes == "Created through LorvexCore.")
  let detailUpdated = try await LorvexSystemIntentRunner.updateTask(
    id: " \(created.id) ",
    title: "  Shared system updated task  ",
    notes: "  Updated through shared runner  ",
    priority: 3,
    estimatedMinutes: 20,
    plannedDate: " 2026-05-28 ",
    tagsText: " system apple ",
    dependsOnText: nil,
    core: core
  )
  #expect(detailUpdated.id == created.id)
  #expect(detailUpdated.title == "Shared system updated task")
  #expect(detailUpdated.notes == "Updated through shared runner")
  #expect(detailUpdated.priority == .p3)
  #expect(detailUpdated.estimatedMinutes == 20)
  // Tags added in one write surface alphabetically (shared created_at).
  #expect(detailUpdated.tags == ["apple", "system"])

  let lifecycleTask = try await core.createTask(title: "Shared system lifecycle task", notes: "")
  let cancelledTitle = try await LorvexSystemIntentRunner.cancelTask(
    id: " \(lifecycleTask.id) ",
    core: core
  )
  #expect(cancelledTitle == "Shared system lifecycle task")
  #expect(try await core.loadTask(id: lifecycleTask.id).status == .cancelled)
  let reopenedTitle = try await LorvexSystemIntentRunner.reopenTask(
    id: " \(lifecycleTask.id) ",
    core: core
  )
  #expect(reopenedTitle == "Shared system lifecycle task")
  // Read the row: undated work has no claim on today, so the day pool cannot
  // witness a status round-trip.
  #expect(try await core.loadTask(id: lifecycleTask.id).status == .open)
}
