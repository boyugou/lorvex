import AppIntents
import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing
import UniformTypeIdentifiers

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func checklistIntentPerformThrowsOnBlankInputs() async throws {
  let task = LorvexTaskEntity(id: "task-id", title: "", status: "")
  let add = AddLorvexChecklistItemIntent(task: task, text: "   ")
  await #expect(throws: LorvexCoreError.self) {
    _ = try await add.perform()
  }

  let toggle = ToggleLorvexChecklistItemIntent(itemID: "   ", completed: true)
  await #expect(throws: LorvexCoreError.self) {
    _ = try await toggle.perform()
  }

  let update = UpdateLorvexChecklistItemIntent(itemID: "item-id", text: "   ")
  await #expect(throws: LorvexCoreError.self) {
    _ = try await update.perform()
  }

  // Destructive: confirms before validating, so perform() surfaces the
  // confirmation gate rather than a core error in a unit test.
  let remove = RemoveLorvexChecklistItemIntent(itemID: "   ")
  await #expect(throws: (any Error).self) {
    _ = try await remove.perform()
  }
}

@Test
func recurrenceIntentPerformThrowsOnInvalidInputs() async throws {
  let task = LorvexTaskEntity(id: "task-id", title: "Task", status: "open")
  let blankTask = LorvexTaskEntity(id: "   ", title: "", status: "")

  let setBlankTask = SetLorvexTaskRecurrenceIntent(task: blankTask, frequency: .weekly)
  await #expect(throws: LorvexCoreError.self) {
    _ = try await setBlankTask.perform()
  }

  let setBadInterval = SetLorvexTaskRecurrenceIntent(
    task: task,
    frequency: .weekly,
    interval: 0
  )
  await #expect(throws: LorvexCoreError.self) {
    _ = try await setBadInterval.perform()
  }

  let setBadWeekday = SetLorvexTaskRecurrenceIntent(
    task: task,
    frequency: .weekly,
    weekdays: "XX"
  )
  await #expect(throws: LorvexCoreError.self) {
    _ = try await setBadWeekday.perform()
  }

  // Destructive: confirms before validating, so perform() surfaces the
  // confirmation gate rather than a core error in a unit test.
  let remove = RemoveLorvexTaskRecurrenceIntent(task: blankTask)
  await #expect(throws: (any Error).self) {
    _ = try await remove.perform()
  }

  let addException = AddLorvexTaskRecurrenceExceptionIntent(task: task, exceptionDate: "   ")
  await #expect(throws: LorvexCoreError.self) {
    _ = try await addException.perform()
  }

  // Destructive: confirms before validating, so perform() surfaces the
  // confirmation gate rather than a core error in a unit test.
  let removeException = RemoveLorvexTaskRecurrenceExceptionIntent(task: blankTask, exceptionDate: "2026-06-01")
  await #expect(throws: (any Error).self) {
    _ = try await removeException.perform()
  }
}
