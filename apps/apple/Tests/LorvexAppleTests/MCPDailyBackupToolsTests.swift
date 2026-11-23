import Foundation
import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

@Suite("MCP Daily Backup Tools")
struct MCPDailyBackupToolsTests {
  /// A registry over a fresh on-disk store, its service, and the folder to
  /// remove afterwards. Daily backups live beside an on-disk database only.
  private func onDiskRegistry() -> (ToolRegistry, SwiftLorvexCoreService, URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-mcp-backups-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = directory.appendingPathComponent("db.sqlite").path
    let service = SwiftLorvexCoreService(databasePath: path)
    return (
      ToolRegistry(coreBridge: CoreBridgeClient(databasePath: path, service: service)),
      service, directory
    )
  }

  private func createTask(
    _ registry: ToolRegistry, _ arguments: [String: Value]
  ) async throws -> String {
    let created = try await mcpRegistryCall(registry, tool: "create_task", arguments: arguments)
    return try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
  }

  private func fenced(_ text: String) -> String {
    let wrapped: String = SecurityFencing.fence(text)
    return wrapped
  }

  private func category(_ result: CallTool.Result, _ name: String) throws -> [String: Value] {
    let object = try #require(result.structuredContent?.objectValue)
    return try #require(object["categories"]?.objectValue?[name]?.objectValue)
  }

  @Test("list_daily_backups lists this store's backups, newest first")
  func listsBackups() async throws {
    let (registry, service, directory) = onDiskRegistry()
    defer { try? FileManager.default.removeItem(at: directory) }

    let empty = try await mcpRegistryCall(registry, tool: "list_daily_backups", arguments: [:])
    #expect(empty.isError != true)
    #expect(empty.structuredContent?.objectValue?["enabled"]?.boolValue == true)
    #expect(empty.structuredContent?.objectValue?["backups"]?.arrayValue?.isEmpty == true)

    _ = try await createTask(registry, ["title": "Keep me"])
    _ = try await service.writeDailyBackupIfDue(day: "2026-11-21", appVersion: nil, now: Date())
    _ = try await service.writeDailyBackupIfDue(day: "2026-11-22", appVersion: nil, now: Date())

    let listed = try await mcpRegistryCall(registry, tool: "list_daily_backups", arguments: [:])
    let backups = try #require(listed.structuredContent?.objectValue?["backups"]?.arrayValue)
    #expect(backups.compactMap { $0.objectValue?["day"]?.stringValue } == ["2026-11-22", "2026-11-21"])
    #expect(backups.allSatisfy { ($0.objectValue?["byte_count"]?.intValue ?? 0) > 0 })
    #expect(backups.allSatisfy { $0.objectValue?["taken_at"]?.stringValue != nil })
  }

  /// Every user-written field the comparison returns arrives fenced, including
  /// the keys only this tool adds to the fencing policy: a tag's display name
  /// and a memory entry's key.
  @Test("compare_with_daily_backup returns removed, added, and changed records, fenced")
  func comparesWithBackup() async throws {
    let (registry, service, directory) = onDiskRegistry()
    defer { try? FileManager.default.removeItem(at: directory) }

    let removed = try await createTask(
      registry,
      [
        "title": "Call the plumber", "notes": "Ask about the boiler", "tags": ["Home repairs"],
        "checklist": ["Shut off the water"],
      ])
    let changed = try await createTask(registry, ["title": "Draft the report", "notes": "Outline"])
    _ = try await mcpRegistryCall(
      registry, tool: "write_memory", arguments: ["key": "Pet name", "content": "Biscuit"])
    _ = try await service.writeDailyBackupIfDue(day: "2026-11-22", appVersion: nil, now: Date())

    _ = try await mcpRegistryCall(registry, tool: "archive_task", arguments: ["id": .string(removed)])
    let erased = try await mcpRegistryCall(
      registry, tool: "permanent_delete_task", arguments: ["id": .string(removed)])
    #expect(erased.isError != true)
    _ = try await mcpRegistryCall(
      registry, tool: "update_task",
      arguments: ["id": .string(changed), "notes": "Outline and first section"])
    _ = try await createTask(registry, ["title": "Book the venue", "tags": ["Venue"]])
    _ = try await mcpRegistryCall(registry, tool: "delete_memory", arguments: ["key": "Pet name"])

    let result = try await mcpRegistryCall(
      registry, tool: "compare_with_daily_backup", arguments: ["day": "2026-11-22"])
    #expect(result.isError != true)

    let tasks = try category(result, "tasks")
    let gone = try #require(tasks["removed"]?.arrayValue?.first?.objectValue)
    #expect(tasks["removed_count"]?.intValue == 1)
    #expect(gone["id"]?.stringValue == removed)
    #expect(gone["title"]?.stringValue == fenced("Call the plumber"))
    #expect(gone["notes"]?.stringValue == fenced("Ask about the boiler"))
    #expect(gone["tags"]?.arrayValue == [.string(fenced("home repairs"))])
    let step = try #require(gone["checklist"]?.arrayValue?.first?.objectValue)
    #expect(step["text"]?.stringValue == fenced("Shut off the water"))

    let added = try #require(tasks["added"]?.arrayValue?.first?.objectValue)
    #expect(added["title"]?.stringValue == fenced("Book the venue"))

    let edit = try #require(tasks["changed"]?.arrayValue?.first?.objectValue)
    #expect(tasks["changed_count"]?.intValue == 1)
    #expect(edit["id"]?.stringValue == changed)
    #expect(edit["title"]?.stringValue == fenced("Draft the report"))
    #expect(edit["backup"]?.objectValue?["notes"]?.stringValue == fenced("Outline"))
    #expect(
      edit["now"]?.objectValue?["notes"]?.stringValue
        == fenced("Outline and first section"))
    #expect(edit["backup"]?.objectValue?["updated_at"] == nil, "updated_at is never compared")

    let tags = try category(result, "tags")
    let tag = try #require(tags["added"]?.arrayValue?.first?.objectValue)
    #expect(tag["display_name"]?.stringValue?.lowercased() == fenced("venue"))

    let memory = try category(result, "memory")
    let entry = try #require(memory["removed"]?.arrayValue?.first?.objectValue)
    #expect(entry["key"]?.stringValue == fenced("Pet name"))
    #expect(entry["content"]?.stringValue == fenced("Biscuit"))

    #expect(mcpSummaryText(result).contains("tasks: 1 removed, 1 added, 1 changed"))
    #expect(result.structuredContent?.objectValue?["backup_taken_at"]?.stringValue != nil)
  }

  /// A record whose only difference is its timestamps is not changed, and a
  /// changed checklist shows only the step that differs.
  @Test("compare_with_daily_backup ignores timestamp-only edits and shows only the differing step")
  func showsOnlyRealChanges() async throws {
    let (registry, service, directory) = onDiskRegistry()
    defer { try? FileManager.default.removeItem(at: directory) }

    func stepIDs(_ taskID: String) async throws -> [String] {
      let task = try await mcpRegistryCall(
        registry, tool: "get_task", arguments: ["id": .string(taskID)])
      let items = try #require(task.structuredContent?.objectValue?["checklist_items"]?.arrayValue)
      return items.compactMap { $0.objectValue?["id"]?.stringValue }
    }
    func toggle(_ itemID: String, _ completed: Bool) async throws {
      let toggled = try await mcpRegistryCall(
        registry, tool: "toggle_task_checklist_item",
        arguments: ["item_id": .string(itemID), "completed": .bool(completed)])
      #expect(toggled.isError != true)
    }

    let untouched = try await createTask(registry, ["title": "Untouched"])
    let roundTrip = try await createTask(registry, ["title": "Round trip", "checklist": ["Only step"]])
    let steps = try await createTask(registry, ["title": "Two steps", "checklist": ["One", "Two"]])
    _ = try await service.writeDailyBackupIfDue(day: "2026-11-22", appVersion: nil, now: Date())

    let roundTripStep = try #require(try await stepIDs(roundTrip).first)
    try await toggle(roundTripStep, true)
    try await toggle(roundTripStep, false)
    let firstStep = try #require(try await stepIDs(steps).first)
    try await toggle(firstStep, true)

    let result = try await mcpRegistryCall(
      registry, tool: "compare_with_daily_backup",
      arguments: ["day": "2026-11-22", "entities": ["tasks"]])
    let tasks = try category(result, "tasks")
    let changed = try #require(tasks["changed"]?.arrayValue)
    #expect(changed.compactMap { $0.objectValue?["id"]?.stringValue } == [steps])
    #expect(!changed.contains { $0.objectValue?["id"]?.stringValue == untouched })

    let edit = try #require(changed.first?.objectValue)
    let before = try #require(edit["backup"]?.objectValue?["checklist"]?.arrayValue)
    let after = try #require(edit["now"]?.objectValue?["checklist"]?.arrayValue)
    #expect(before.count == 1 && after.count == 1, "the untouched step is left out")
    #expect(before.first?.objectValue?["text"]?.stringValue == fenced("One"))
    #expect(before.first?.objectValue?["completed"]?.boolValue == false)
    #expect(after.first?.objectValue?["completed"]?.boolValue == true)
  }

  /// Field names follow the export's snake_case, with an `IDs` suffix kept
  /// whole rather than split into `i_ds`.
  @Test("records use the export's snake_case field names")
  func usesSnakeCaseNames() throws {
    #expect(DailyBackupComparison.snakeCase("linkedTaskIDs") == "linked_task_ids")
    #expect(DailyBackupComparison.snakeCase("calendarEventID") == "calendar_event_id")
    #expect(DailyBackupComparison.snakeCase("startDate") == "start_date")
    #expect(DailyBackupComparison.snakeCase("id") == "id")

    let payload = LorvexDataExportPayload(
      dailyReviews: [
        ExportDailyReview(
          date: "2026-11-22", summary: "", mood: nil, energyLevel: nil, wins: "", blockers: "",
          learnings: "", timezone: nil, updatedAt: nil, linkedTaskIDs: ["t1"], linkedListIDs: [])
      ])
    let review = try #require(
      try DailyBackupComparison.records(of: payload)["daily_reviews"]?.first?.objectValue)
    #expect(review["linked_task_ids"]?.arrayValue == [.string("t1")])
    #expect(review["linked_list_ids"]?.arrayValue == [])
  }

  @Test("compare_with_daily_backup narrows by category, ids, and limit")
  func narrowsTheComparison() async throws {
    let (registry, service, directory) = onDiskRegistry()
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = try await createTask(registry, ["title": "First", "notes": "a"])
    let second = try await createTask(registry, ["title": "Second", "notes": "b"])
    _ = try await service.writeDailyBackupIfDue(day: "2026-11-22", appVersion: nil, now: Date())
    for (id, notes) in [(first, "a2"), (second, "b2")] {
      _ = try await mcpRegistryCall(
        registry, tool: "update_task", arguments: ["id": .string(id), "notes": .string(notes)])
    }

    let onlySecond = try await mcpRegistryCall(
      registry, tool: "compare_with_daily_backup",
      arguments: ["day": "2026-11-22", "entities": ["tasks"], "ids": .array([.string(second)])])
    let tasks = try category(onlySecond, "tasks")
    #expect(tasks["changed"]?.arrayValue?.compactMap { $0.objectValue?["id"]?.stringValue } == [second])
    let object = try #require(onlySecond.structuredContent?.objectValue)
    #expect(object["categories"]?.objectValue?.keys.sorted() == ["tasks"])

    let limited = try await mcpRegistryCall(
      registry, tool: "compare_with_daily_backup",
      arguments: ["day": "2026-11-22", "entities": ["tasks"], "limit": 1])
    let limitedTasks = try category(limited, "tasks")
    #expect(limitedTasks["changed"]?.arrayValue?.count == 1)
    #expect(limitedTasks["changed_count"]?.intValue == 2)
    #expect(limited.structuredContent?.objectValue?["truncated"]?.boolValue == true)
  }

  @Test("compare_with_daily_backup refuses a malformed day, an unknown category, and a missing backup")
  func refusesBadArguments() async throws {
    let (registry, _, directory) = onDiskRegistry()
    defer { try? FileManager.default.removeItem(at: directory) }

    for arguments: [String: Value] in [
      ["day": "yesterday"],
      ["day": "2026-02-30"],
      ["day": "2026-11-22", "entities": ["preferences"]],
      ["day": "2026-11-22", "entities": .array([])],
      ["day": "2026-11-22", "limit": 0],
    ] {
      let result = try await mcpRegistryCall(
        registry, tool: "compare_with_daily_backup", arguments: arguments)
      #expect(result.isError == true, "\(arguments)")
    }
    let missing = try await mcpRegistryCall(
      registry, tool: "compare_with_daily_backup", arguments: ["day": "2026-11-22"])
    #expect(missing.isError == true)
    #expect(mcpTextContent(missing).contains("no daily backup from 2026-11-22"))
  }
}
