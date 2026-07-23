import Foundation
import Testing

@testable import LorvexCore

/// The list / habit / calendar entity lookups throw the typed
/// `LorvexCoreError.notFound(entity:id:)` on a miss. Two contracts are pinned:
/// the service raises the typed case (so callers can branch on it), and the
/// case's `errorDescription` reproduces the exact "<Noun> '<id>' not found."
/// sentence the migration replaced — the property every message-matching
/// consumer (MCP envelope text, `error_logs`, the UI string fallback) depends on.
@Suite("SwiftLorvexCoreService typed not-found")
struct SwiftLorvexCoreServiceNotFoundTypedTests {
  private let bad = "0192f3a1-7c4b-7def-9abc-1234567890ab"

  @Test("getList of a missing list throws .notFound(.list)")
  func getListThrowsTypedNotFound() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    await #expect(throws: LorvexCoreError.notFound(entity: .list, id: bad)) {
      _ = try await service.getList(id: bad)
    }
  }

  @Test("getHabitStats of a missing habit throws .notFound(.habit)")
  func getHabitStatsThrowsTypedNotFound() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    await #expect(throws: LorvexCoreError.notFound(entity: .habit, id: bad)) {
      _ = try await service.getHabitStats(id: bad)
    }
  }

  @Test("adding an exception to a missing calendar event throws .notFound(.calendarEvent)")
  func calendarEventExceptionThrowsTypedNotFound() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    await #expect(throws: LorvexCoreError.notFound(entity: .calendarEvent, id: bad)) {
      _ = try await service.addCalendarEventException(eventID: bad, date: "2026-01-01")
    }
  }

  @Test("errorDescription reproduces the historical sentence for every entity kind")
  func errorDescriptionByteParity() {
    #expect(
      LorvexCoreError.notFound(entity: .list, id: bad).errorDescription
        == "List '\(bad)' not found.")
    #expect(
      LorvexCoreError.notFound(entity: .habit, id: bad).errorDescription
        == "Habit '\(bad)' not found.")
    #expect(
      LorvexCoreError.notFound(entity: .calendarEvent, id: bad).errorDescription
        == "Calendar event '\(bad)' not found.")
    #expect(
      LorvexCoreError.notFound(entity: .calendarSeries, id: bad).errorDescription
        == "Calendar series '\(bad)' not found.")
    // A nil id drops the quoted id but keeps the noun (unused by migrated sites,
    // which always carry an id — pinned so the shape is intentional).
    #expect(LorvexCoreError.notFound(entity: .list, id: nil).errorDescription == "List not found.")
  }

  @Test("entity display nouns match the migrated wording")
  func entityDisplayNames() {
    #expect(LorvexEntityKind.list.displayName == "List")
    #expect(LorvexEntityKind.habit.displayName == "Habit")
    #expect(LorvexEntityKind.calendarEvent.displayName == "Calendar event")
    #expect(LorvexEntityKind.calendarSeries.displayName == "Calendar series")
  }
}
