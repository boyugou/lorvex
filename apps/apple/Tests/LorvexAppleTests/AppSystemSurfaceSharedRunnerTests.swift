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

// A Shortcuts update that names one field once rewrote every field from a
// read-back and took the planned day from the deadline, so renaming a task
// moved it to its due date (or cleared its day when it had no deadline) and
// dropped its time.
@Test
func sharedSystemIntentUpdateWritesOnlyTheFieldsItNames() async throws {
  let core = try await makeSeededInMemoryCore()
  let plannedDay = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-07-14"))
  let dueDay = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-07-20"))
  let task = try await core.updateTask(
    TaskUpdateDraft(
      id: try await core.createTask(title: "Draft the launch post", notes: "Outline first").id,
      priority: .p1, estimatedMinutes: .set(50), dueDate: .set(dueDay),
      plannedDate: .set(plannedDay), plannedTime: .set(600..<650), tags: ["launch"]))

  let renamed = try await LorvexSystemIntentRunner.updateTask(
    id: task.id, title: "Write the launch post", notes: nil, priority: nil,
    estimatedMinutes: nil, plannedDate: nil, tagsText: nil, dependsOnText: nil, core: core)

  #expect(renamed.title == "Write the launch post")
  #expect(renamed.notes == "Outline first")
  #expect(renamed.priority == .p1)
  #expect(renamed.estimatedMinutes == 50)
  #expect(renamed.plannedDate == plannedDay)
  #expect(renamed.plannedTime == 600..<650)
  #expect(renamed.dueDate == dueDay)
  #expect(renamed.tags == ["launch"])

  // A blank planned date still clears the day, and with it the time.
  let cleared = try await LorvexSystemIntentRunner.updateTask(
    id: task.id, title: nil, notes: nil, priority: nil, estimatedMinutes: nil,
    plannedDate: "  ", tagsText: nil, dependsOnText: nil, core: core)
  #expect(cleared.plannedDate == nil)
  #expect(cleared.plannedTime == nil)
  #expect(cleared.dueDate == dueDay)
}
