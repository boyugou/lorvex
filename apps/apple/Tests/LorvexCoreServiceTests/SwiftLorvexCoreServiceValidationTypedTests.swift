import Foundation
import Testing

@testable import LorvexCore

/// The App-Intents input validators (`LorvexSystemIntentRunner`) throw the typed
/// `LorvexCoreError.validation(field:message:)` on a caller-input constraint
/// violation. Two contracts are pinned: the runner raises the typed case (so
/// callers can branch on it and read `field`), and the case's `errorDescription`
/// reproduces the exact human sentence the migration replaced verbatim — the
/// property every consumer (App-Intents error display, the UI string classifier)
/// depends on. `field` is metadata only: it never appears in the rendered
/// message and never changes classification (see ``UserFacingErrorTests``).
@Suite("LorvexSystemIntentRunner typed validation")
struct SwiftLorvexCoreServiceValidationTypedTests {
  @Test("an empty task id throws .validation(field: task_id)")
  func emptyTaskIDThrowsTypedValidation() {
    #expect(
      throws: LorvexCoreError.validation(field: "task_id", message: "A task ID is required.")
    ) {
      _ = try LorvexSystemIntentRunner.validatedTaskID("   ")
    }
  }

  @Test("an empty list id throws .validation(field: list_id)")
  func emptyListIDThrowsTypedValidation() {
    #expect(
      throws: LorvexCoreError.validation(field: "list_id", message: "A list ID is required.")
    ) {
      _ = try LorvexSystemIntentRunner.validatedListID("")
    }
  }

  @Test("an empty habit id throws .validation(field: habit_id)")
  func emptyHabitIDThrowsTypedValidation() {
    #expect(
      throws: LorvexCoreError.validation(field: "habit_id", message: "A habit ID is required.")
    ) {
      _ = try LorvexSystemIntentRunner.validatedHabitID("")
    }
  }

  @Test("an out-of-range priority throws .validation(field: priority)")
  func outOfRangePriorityThrowsTypedValidation() {
    #expect(
      throws: LorvexCoreError.validation(
        field: "priority", message: "Task priority must be 1, 2, or 3.")
    ) {
      _ = try LorvexSystemIntentRunner.parsedPriority(4)
    }
  }

  @Test("a non-positive recurrence interval throws .validation(field: interval)")
  func nonPositiveRecurrenceIntervalThrowsTypedValidation() {
    #expect(
      throws: LorvexCoreError.validation(
        field: "interval", message: "Recurrence interval must be greater than zero.")
    ) {
      _ = try LorvexSystemIntentRunner.validatedRecurrenceInterval(0)
    }
  }

  @Test("an empty search query throws .validation(field: query) through the core path")
  func emptySearchQueryThrowsTypedValidation() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    await #expect(
      throws: LorvexCoreError.validation(
        field: "query", message: "A task search query is required.")
    ) {
      _ = try await LorvexSystemIntentRunner.searchTasks(
        query: "   ", status: nil, limit: nil, offset: nil, core: service)
    }
  }

  @Test("a focus task block requires a canonical task UUID")
  func focusTaskBlockRejectsNoncanonicalTaskID() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    await #expect(
      throws: LorvexCoreError.validation(
        field: "task_id",
        message: "Focus schedule 'task' block requires a canonical task UUID.")
    ) {
      _ = try await service.saveFocusSchedule(
        date: "2026-07-16",
        blocks: [
          FocusScheduleBlock(
            blockType: "task", startTime: "09:00", endTime: "10:00",
            taskID: "not-a-uuid", title: "Invalid task")
        ],
        rationale: nil)
    }
  }

  @Test("errorDescription reproduces the message verbatim and ignores field")
  func errorDescriptionByteParity() {
    #expect(
      LorvexCoreError.validation(field: "task_id", message: "A task ID is required.")
        .errorDescription == "A task ID is required.")
    #expect(
      LorvexCoreError.validation(field: nil, message: "A tag is required.")
        .errorDescription == "A tag is required.")
    // The same message with different `field` values renders identically — the
    // annotation is caller metadata, never part of the surfaced sentence.
    #expect(
      LorvexCoreError.validation(field: "priority", message: "Task priority must be 1, 2, or 3.")
        .errorDescription
        == LorvexCoreError.validation(field: nil, message: "Task priority must be 1, 2, or 3.")
        .errorDescription)
  }
}
