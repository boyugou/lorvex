import AppIntents
import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing
import UniformTypeIdentifiers

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func tagIntentPerformThrowsOnBlankTag() async throws {
  let rename = RenameLorvexTagIntent(oldTag: "   ", newTag: "apple")
  await #expect(throws: LorvexCoreError.self) {
    _ = try await rename.perform()
  }

  let find = FindLorvexTasksByTagIntent(tag: "   ")
  await #expect(throws: LorvexCoreError.self) {
    _ = try await find.perform()
  }
}

@Test
func taskContentIntentPerformThrowsOnBlankInputs() async throws {
  let task = LorvexTaskEntity(id: "   ", title: "", status: "")
  let updateBlankTask = UpdateLorvexTaskIntent(task: task, title: "Renamed")
  await #expect(throws: LorvexCoreError.self) {
    _ = try await updateBlankTask.perform()
  }

  let updateBlankTitle = UpdateLorvexTaskIntent(
    task: LorvexTaskEntity(id: "task-id", title: "", status: ""),
    title: "   "
  )
  await #expect(throws: LorvexCoreError.self) {
    try await withIsolatedAppIntentDatabase {
      _ = try await updateBlankTitle.perform()
    }
  }

  let updateBadPriority = UpdateLorvexTaskIntent(
    task: LorvexTaskEntity(id: "task-id", title: "", status: ""),
    priority: 4
  )
  await #expect(throws: LorvexCoreError.self) {
    try await withIsolatedAppIntentDatabase {
      _ = try await updateBadPriority.perform()
    }
  }

  let append = AppendLorvexTaskBodyIntent(task: task, text: "Notes")
  await #expect(throws: LorvexCoreError.self) {
    _ = try await append.perform()
  }

  let reminders = SetLorvexTaskRemindersIntent(
    task: LorvexTaskEntity(id: "task-id", title: "", status: ""),
    reminders: " , \n "
  )
  await #expect(throws: LorvexCoreError.self) {
    _ = try await reminders.perform()
  }
}

@Test
func reminderIntentPerformThrowsOnInvalidInputs() async throws {
  let task = LorvexTaskEntity(id: "task-id", title: "Task", status: "open")
  let blankTask = LorvexTaskEntity(id: "   ", title: "", status: "")

  let addBlankTask = AddLorvexTaskReminderIntent(task: blankTask, reminderAt: "2026-06-01T09:00:00Z")
  await #expect(throws: LorvexCoreError.self) {
    _ = try await addBlankTask.perform()
  }

  let addBlankTimestamp = AddLorvexTaskReminderIntent(task: task, reminderAt: "   ")
  await #expect(throws: LorvexCoreError.self) {
    _ = try await addBlankTimestamp.perform()
  }

  // Destructive: confirms before validating, so perform() surfaces the
  // confirmation gate rather than a core error in a unit test.
  let removeBlankReminder = RemoveLorvexTaskReminderIntent(task: task, reminderID: "   ")
  await #expect(throws: (any Error).self) {
    _ = try await removeBlankReminder.perform()
  }

  let dueBadLimit = ReadLorvexDueTaskRemindersIntent(limit: 0)
  await #expect(throws: LorvexCoreError.self) {
    _ = try await dueBadLimit.perform()
  }

  let upcomingBadHorizon = ReadLorvexUpcomingTaskRemindersIntent(hoursAhead: 0)
  await #expect(throws: LorvexCoreError.self) {
    _ = try await upcomingBadHorizon.perform()
  }
}

@Test
func batchTaskIntentPerformThrowsOnInvalidInputs() async throws {
  await #expect(throws: LorvexCoreError.self) {
    _ = try await BatchCreateLorvexTasksIntent(titles: "   ").perform()
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await BatchCreateLorvexTasksIntent(titles: "task", priority: 9).perform()
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await BatchCompleteLorvexTasksIntent(tasks: []).perform()
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await BatchReopenLorvexTasksIntent(tasks: []).perform()
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await BatchDeferLorvexTasksIntent(
      tasks: [LorvexTaskEntity(id: "task-id", title: "", status: "")],
      until: "bad-date"
    ).perform()
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await BatchMoveLorvexTasksIntent(
      tasks: [LorvexTaskEntity(id: "task-id", title: "", status: "")],
      list: LorvexListEntity(id: "   ", name: "", openCount: 0, totalCount: 0)
    ).perform()
  }
}
