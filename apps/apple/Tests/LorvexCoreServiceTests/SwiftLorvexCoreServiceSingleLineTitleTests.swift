import Foundation
import LorvexStore
import XCTest

@testable import LorvexCore

/// A title or a name draws on one line everywhere it is shown, so the core folds
/// line breaks to a space on every local write path (a multi-line paste into the
/// Mac inspector, or a multi-line argument from the assistant, used to be stored
/// as typed and grew or cut off the rows that show it).
final class SwiftLorvexCoreServiceSingleLineTitleTests: XCTestCase {
  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // LorvexCoreServiceTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(
      schemaSQL: schemaSQL, migrations: try SwiftLorvexCoreService.resolveSchemaMigrations())
    return SwiftLorvexCoreService(store: store)
  }

  func testTaskTitleFoldsLineBreaksOnCreateAndUpdate() async throws {
    let service = try makeService()
    let created = try await service.createTask(title: "Buy milk\nand eggs\r\n", notes: "one\ntwo")
    XCTAssertEqual(created.title, "Buy milk and eggs")

    let updated = try await service.updateTask(
      id: created.id, title: "  Call\nthe\tbank  ", notes: "one\ntwo", priority: .p3,
      estimatedMinutes: nil, dueDate: nil, plannedDate: nil, availableFrom: nil, tags: [],
      dependsOn: [])
    XCTAssertEqual(updated.title, "Call the bank")
  }

  func testTaskUpdateSanitizesTheFreeTextItStores() async throws {
    // The update path used to store a title and a note exactly as given.
    let service = try makeService()
    let created = try await service.createTask(title: "Plain", notes: "")
    let updated = try await service.updateTask(
      id: created.id, title: "Ad\u{200B}min\u{202E}", notes: "keep\u{FEFF}this\nnote",
      priority: .p3, estimatedMinutes: nil, dueDate: nil, plannedDate: nil, availableFrom: nil,
      tags: [], dependsOn: [])
    XCTAssertEqual(updated.title, "Admin")
    XCTAssertEqual(updated.notes, "keepthis\nnote", "a note keeps its line breaks")
  }

  func testATaskTitleOfOnlyLineBreaksIsEmpty() async throws {
    let service = try makeService()
    do {
      _ = try await service.createTask(title: "\n \r\n\t", notes: "")
      XCTFail("a title with nothing but line breaks must be refused")
    } catch {
      // Refused as an empty title.
    }
  }

  func testListNameFoldsLineBreaks() async throws {
    let service = try makeService()
    let list = try await service.createList(
      name: "Home\nrepairs", description: nil, color: nil, icon: nil, aiNotes: nil)
    XCTAssertEqual(list.name, "Home repairs")

    let renamed = try await service.updateList(
      id: list.id, name: "Home\r\nand garden", description: .unset, color: nil, icon: nil,
      aiNotes: nil)
    XCTAssertEqual(renamed.name, "Home and garden")
  }

  func testHabitNameFoldsLineBreaks() async throws {
    let service = try makeService()
    let habit = try await service.createHabit(
      name: "Read\n30 minutes", cue: nil, icon: nil, color: nil, targetCount: 1, cadence: .daily)
    XCTAssertEqual(habit.name, "Read 30 minutes")
  }

  func testCalendarEventTitleFoldsLineBreaks() async throws {
    let service = try makeService()
    let event = try await service.createCalendarEvent(
      title: "Team\nstandup", startDate: "2026-06-01", endDate: nil, startTime: "09:00",
      endTime: "09:30", allDay: false, location: nil, notes: nil, recurrence: nil,
      timezone: "America/Los_Angeles", url: nil, color: nil, eventType: nil, personName: nil,
      attendees: nil)
    XCTAssertEqual(event.title, "Team standup")
  }
}
