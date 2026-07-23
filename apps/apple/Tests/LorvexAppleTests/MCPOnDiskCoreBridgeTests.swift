import Foundation
import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

struct MCPOnDiskCoreBridgeTests {
  @Test("MCP reads records seeded directly through the on-disk Swift core")
  func mcpReadsSeededOnDiskSwiftCoreRecords() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let seedCore = SwiftLorvexCoreService(databasePath: fixture.dbPath)
    let seededTask = try await seedCore.createTask(
      title: "Seeded Swift core task",
      notes: "Inserted before the MCP bridge reads the database"
    )
    _ = try await seedCore.upsertMemory(key: "seeded_context", content: "Seeded memory body")

    let fetchedTask = try await mcpRegistryCall(
      fixture.registry,
      tool: "get_task",
      arguments: ["id": .string(seededTask.id)]
    )
    #expect(fetchedTask.isError != true)
    let taskObject = try #require(fetchedTask.structuredContent?.objectValue)
    let fencedTaskTitle: String = SecurityFencing.fence("Seeded Swift core task")
    let fencedTaskNotes: String = SecurityFencing.fence(
      "Inserted before the MCP bridge reads the database")
    #expect(taskObject["id"]?.stringValue == seededTask.id)
    #expect(taskObject["title"]?.stringValue == fencedTaskTitle)
    #expect(taskObject["notes"]?.stringValue == fencedTaskNotes)

    let memory = try await mcpRegistryCall(
      fixture.registry,
      tool: "read_memory",
      arguments: ["key": .string("seeded_context")]
    )
    #expect(memory.isError != true)
    let memoryEntries = try #require(
      memory.structuredContent?.objectValue?["entries"]?.arrayValue)
    let fencedMemoryBody: String = SecurityFencing.fence("Seeded memory body")
    // Both the key and the content are fenced as user content (MCP-1 / Rule 6).
    let fencedMemoryKey: String = SecurityFencing.fence("seeded_context")
    #expect(
      memoryEntries.contains {
        $0.objectValue?["key"]?.stringValue == fencedMemoryKey
          && $0.objectValue?["content"]?.stringValue == fencedMemoryBody
      })
  }

  @Test("list_all_tags drops a tag once its only task is archived")
  func listAllTagsDropsArchivedOnlyTaskTag() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let created = try await mcpRegistryCall(
      fixture.registry, tool: "create_task", arguments: ["title": .string("Tagged task")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    _ = try await mcpRegistryCall(
      fixture.registry, tool: "update_task",
      arguments: ["id": .string(taskID), "tags_set": .array([.string("alpha")])])

    let fencedAlpha: String = SecurityFencing.fence("alpha")
    let before = try await mcpRegistryCall(fixture.registry, tool: "list_all_tags")
    #expect(
      (before.structuredContent?.objectValue?["tags"]?.arrayValue ?? [])
        .contains { $0.stringValue == fencedAlpha })

    // Archiving the only task carrying the tag drops it from list_all_tags: the
    // tag row is kept (no usage-GC), but it is no longer on a non-archived task.
    _ = try await mcpRegistryCall(
      fixture.registry, tool: "archive_task", arguments: ["id": .string(taskID)])
    let after = try await mcpRegistryCall(fixture.registry, tool: "list_all_tags")
    #expect(
      !(after.structuredContent?.objectValue?["tags"]?.arrayValue ?? [])
        .contains { $0.stringValue == fencedAlpha })
  }

  @Test("batch_create_tasks include_advice surfaces intake nudges")
  func batchCreateAdviceSurfacesNudges() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let result = try await mcpRegistryCall(
      fixture.registry, tool: "batch_create_tasks",
      arguments: [
        "include_advice": .bool(true),
        "tasks": .array([.object(["title": .string("Advice probe task")])]),
      ])
    #expect(result.isError != true)
    // An open task with no estimate and no planned date earns both field nudges.
    let advice = try #require(result.structuredContent?.objectValue?["advice"]?.arrayValue)
    #expect(advice.count == 1)
    let codes = Set(
      (advice.first?.objectValue?["advice"]?.arrayValue ?? [])
        .compactMap { $0.objectValue?["code"]?.stringValue })
    #expect(codes.contains("missing_estimate"))
    #expect(codes.contains("missing_planned_date"))

    // Without include_advice the field stays null (no behavior change).
    let plain = try await mcpRegistryCall(
      fixture.registry, tool: "batch_create_tasks",
      arguments: ["tasks": .array([.object(["title": .string("No advice task")])])])
    let plainAdvice = plain.structuredContent?.objectValue?["advice"]?.arrayValue ?? []
    #expect(plainAdvice.isEmpty)
  }

  @Test("batch_create_tasks and batch_update_tasks apply rich fields through the on-disk bridge")
  func batchTaskMutationsApplyRichFieldsOnDisk() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let single = try await mcpRegistryCall(
      fixture.registry, tool: "create_task",
      arguments: [
        "title": .string("Rich on-disk single task"),
        "list_id": .string("inbox"),
        "priority": .int(1),
        "estimated_minutes": .int(25),
        "due_date": .string("2026-07-05"),
        "planned_date": .string("2026-07-04"),
        "tags_set": .array([.string("disk-single")]),
      ])
    #expect(single.isError != true)
    let singleTask = try #require(single.structuredContent?.objectValue)
    #expect(singleTask["priority"]?.intValue == 1)
    #expect(singleTask["estimated_minutes"]?.intValue == 25)
    #expect(singleTask["due_date"]?.stringValue == "2026-07-05")
    #expect(singleTask["planned_date"]?.stringValue == "2026-07-04")
    #expect(singleTask["tags"]?.arrayValue?.first?.stringValue?.contains("disk-single") == true)

    let created = try await mcpRegistryCall(
      fixture.registry, tool: "batch_create_tasks",
      arguments: [
        "tasks": .array([
          .object([
            "title": .string("Rich on-disk batch task"),
            "estimated_minutes": .int(35),
            "due_date": .string("2026-07-03"),
            "planned_date": .string("2026-07-02"),
            "tags": .array([.string("disk-batch")]),
          ])
        ])
      ])
    #expect(created.isError != true)
    let task = try #require(created.structuredContent?.objectValue?["results"]?.arrayValue?.first?.objectValue)
    let taskID = try #require(task["id"]?.stringValue)
    #expect(task["estimated_minutes"]?.intValue == 35)
    #expect(task["due_date"]?.stringValue == "2026-07-03")
    #expect(task["planned_date"]?.stringValue == "2026-07-02")

    let updated = try await mcpRegistryCall(
      fixture.registry, tool: "batch_update_tasks",
      arguments: [
        "updates": .array([
          .object([
            "id": .string(taskID),
            "estimated_minutes": .int(50),
            "tags": .array([.string("disk-batch-updated")]),
          ])
        ])
      ])
    #expect(updated.isError != true)
    let updatedTask = try #require(
      updated.structuredContent?.objectValue?["results"]?.arrayValue?.first?.objectValue)
    #expect(updatedTask["estimated_minutes"]?.intValue == 50)
    #expect(updatedTask["tags"]?.arrayValue?.count == 1)
  }

  @Test("tags/tags_set alias resolves with the same precedence on create and update")
  func tagsAliasPrecedenceIsUnified() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    // Both aliases supplied with different values: `tags` wins on create.
    let created = try await mcpRegistryCall(
      fixture.registry, tool: "create_task",
      arguments: [
        "title": .string("Alias precedence"),
        "tags": .array([.string("win")]),
        "tags_set": .array([.string("lose")]),
      ])
    #expect(created.isError != true)
    let createdTask = try #require(created.structuredContent?.objectValue)
    let taskID = try #require(createdTask["id"]?.stringValue)
    let createdTags = (createdTask["tags"]?.arrayValue ?? []).compactMap(\.stringValue)
    #expect(createdTags.count == 1)
    #expect(createdTags.first?.contains("win") == true)

    // The same precedence applies on update — `tags` wins over `tags_set`.
    let updated = try await mcpRegistryCall(
      fixture.registry, tool: "update_task",
      arguments: [
        "id": .string(taskID),
        "tags": .array([.string("win2")]),
        "tags_set": .array([.string("lose2")]),
      ])
    #expect(updated.isError != true)
    let updatedTags =
      (updated.structuredContent?.objectValue?["tags"]?.arrayValue ?? []).compactMap(\.stringValue)
    #expect(updatedTags.count == 1)
    #expect(updatedTags.first?.contains("win2") == true)
  }

  @Test("MCP get_task surfaces last_deferred_at after a defer")
  func getTaskSurfacesLastDeferredAt() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let core = SwiftLorvexCoreService(databasePath: fixture.dbPath)
    let task = try await core.createTask(title: "Defer me", notes: "")
    _ = try await core.deferTask(
      id: task.id, until: Date(timeIntervalSince1970: 1_800_000_000), reason: nil)

    let fetched = try await mcpRegistryCall(
      fixture.registry, tool: "get_task", arguments: ["id": .string(task.id)])
    #expect(fetched.isError != true)
    let obj = try #require(fetched.structuredContent?.objectValue)
    // A system timestamp surfaced unfenced; non-null once the task has been deferred.
    let lastDeferredAt = obj["last_deferred_at"]?.stringValue
    #expect(lastDeferredAt != nil && !(lastDeferredAt ?? "").isEmpty)
    #expect(obj["defer_count"]?.intValue == 1)
  }

  @Test("MCP task writes persist through the on-disk Swift core bridge")
  func taskWritePersistsThroughReopenedBridge() async throws {
    let initial = mcpOnDiskRegistry()
    defer { initial.cleanup() }

    let created = try await mcpRegistryCall(
      initial.registry,
      tool: "create_task",
      arguments: [
        "title": .string("On-disk MCP bridge task"),
        "notes": .string("Created through ToolRegistry(coreBridge:)"),
      ])
    #expect(created.isError != true)
    let createdTask = try #require(created.structuredContent?.objectValue)
    let taskID = try #require(createdTask["id"]?.stringValue)
    let fencedCreatedTitle: String = SecurityFencing.fence("On-disk MCP bridge task")
    #expect(createdTask["title"]?.stringValue == fencedCreatedTitle)

    let reopened = mcpOnDiskRegistry(dbPath: initial.dbPath)
    let fetched = try await mcpRegistryCall(
      reopened.registry,
      tool: "get_task",
      arguments: ["id": .string(taskID)])
    #expect(fetched.isError != true)
    let fetchedTask = try #require(fetched.structuredContent?.objectValue)
    #expect(fetchedTask["id"]?.stringValue == taskID)
    #expect(fetchedTask["title"]?.stringValue?.contains("On-disk MCP bridge task") == true)

    let tasksPage = try await mcpRegistryCall(
      reopened.registry,
      tool: "list_tasks",
      arguments: ["status": .string("open"), "limit": .int(20)])
    #expect(tasksPage.isError != true)
    let listedTasks = try #require(tasksPage.structuredContent?.objectValue?["tasks"]?.arrayValue)
    #expect(listedTasks.contains { $0.objectValue?["id"]?.stringValue == taskID })

    _ = try await mcpRegistryCall(
      reopened.registry,
      tool: "defer_task",
      arguments: ["id": .string(taskID), "until_date": .string("2026-06-01")])
    // Deferral keeps the task open (it pushes planned_date), so it stays in the
    // open list and is surfaced by the defer_count-based get_deferred_tasks.
    let deferredTasksPage = try await mcpRegistryCall(
      reopened.registry,
      tool: "get_deferred_tasks",
      arguments: ["limit": .int(20)])
    #expect(deferredTasksPage.isError != true)
    let listedDeferredTasks = try #require(
      deferredTasksPage.structuredContent?.objectValue?["tasks"]?.arrayValue)
    #expect(listedDeferredTasks.contains { $0.objectValue?["id"]?.stringValue == taskID })

    let deferredSearchPage = try await mcpRegistryCall(
      reopened.registry,
      tool: "search_tasks",
      arguments: [
        "query": .string("On-disk MCP bridge"),
        "status": .string("open"),
        "limit": .int(20),
      ])
    #expect(deferredSearchPage.isError != true)
    let searchedDeferredTasks = try #require(
      deferredSearchPage.structuredContent?.objectValue?["tasks"]?.arrayValue)
    #expect(searchedDeferredTasks.contains { $0.objectValue?["id"]?.stringValue == taskID })

    let changelog = try await mcpRegistryCall(
      reopened.registry,
      tool: "get_ai_changelog",
      arguments: ["limit": .int(20)])
    #expect(changelog.isError != true)
    let entries = try #require(changelog.structuredContent?.objectValue?["entries"]?.arrayValue)
    #expect(entries.contains { entry in
      let object = entry.objectValue
      return object?["entity_type"]?.stringValue == "task"
        && object?["operation"]?.stringValue == "upsert"
        && object?["summary"]?.stringValue?.contains("On-disk MCP bridge task") == true
    })
  }

  @Test("update_task preserves fields the caller omits and rejects malformed dates")
  func updateTaskPreservesOmittedFieldsThroughOnDiskBridge() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let created = try await mcpRegistryCall(
      fixture.registry,
      tool: "create_task",
      arguments: [
        "title": .string("Preserve fields task"),
        "notes": .string("Original notes worth keeping"),
      ])
    #expect(created.isError != true)
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    // Set an estimate and a due date so we can confirm both are preserved when a
    // later update omits them.
    let dated = try await mcpRegistryCall(
      fixture.registry,
      tool: "update_task",
      arguments: [
        "id": .string(taskID),
        "title": .string("Preserve fields task"),
        "estimated_minutes": .int(45),
        "planned_date": .string("2026-07-15"),
      ])
    #expect(dated.isError != true)
    #expect(dated.structuredContent?.objectValue?["estimated_minutes"]?.intValue == 45)

    // Update only the title: notes, estimated_minutes, and planned_date were
    // not supplied, so they must survive rather than be wiped/cleared.
    let updated = try await mcpRegistryCall(
      fixture.registry,
      tool: "update_task",
      arguments: [
        "id": .string(taskID),
        "title": .string("Preserve fields task renamed"),
      ])
    #expect(updated.isError != true)
    let updatedTask = try #require(updated.structuredContent?.objectValue)
    let fencedUpdatedTitle: String = SecurityFencing.fence("Preserve fields task renamed")
    let fencedOriginalNotes: String = SecurityFencing.fence("Original notes worth keeping")
    #expect(updatedTask["title"]?.stringValue == fencedUpdatedTitle)
    #expect(updatedTask["notes"]?.stringValue == fencedOriginalNotes)
    #expect(updatedTask["estimated_minutes"]?.intValue == 45)
    #expect(updatedTask["planned_date"]?.stringValue == "2026-07-15")

    // A malformed (non-empty) planned_date is a validation error, not a silent
    // due-date wipe.
    let malformed = try await mcpRegistryCall(
      fixture.registry,
      tool: "update_task",
      arguments: [
        "id": .string(taskID),
        "title": .string("Preserve fields task renamed"),
        "planned_date": .string("next monday"),
      ])
    #expect(malformed.isError == true)

    // The failed update left the existing due date intact.
    let refetched = try await mcpRegistryCall(
      fixture.registry,
      tool: "get_task",
      arguments: ["id": .string(taskID)])
    #expect(refetched.structuredContent?.objectValue?["planned_date"]?.stringValue == "2026-07-15")

    // defer_task likewise rejects a malformed date instead of deferring to today.
    let badDefer = try await mcpRegistryCall(
      fixture.registry,
      tool: "defer_task",
      arguments: [
        "id": .string(taskID),
        "until_date": .string("06/01/2026"),
      ])
    #expect(badDefer.isError == true)
  }

  @Test("MCP calendar attendees round-trip through on-disk search and timeline reads")
  func calendarAttendeesRoundTripThroughOnDiskReads() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let created = try await mcpRegistryCall(
      fixture.registry,
      tool: "create_calendar_event",
      arguments: [
        "title": .string("On-disk attendee planning"),
        "start_date": .string("2026-06-09"),
        "start_time": .string("08:00"),
        "end_time": .string("08:30"),
        "attendees": .array([
          .object([
            "email": .string("alice@example.com"),
            "name": .string("Alice"),
          ])
        ]),
      ])
    #expect(created.isError != true)
    let createdObject = try #require(created.structuredContent?.objectValue)
    let eventID = try #require(createdObject["event_id"]?.stringValue)
    #expect(createdObject["id"]?.stringValue == eventID)

    let search = try await mcpRegistryCall(
      fixture.registry,
      tool: "search_calendar_events",
      arguments: ["query": .string("attendee planning"), "shape": .string("full")])
    #expect(search.isError != true)
    let searchObject = try #require(search.structuredContent?.objectValue)
    // search_calendar_events rides the shared pagination envelope, not {count}.
    #expect(searchObject["count"] == nil)
    #expect(searchObject["returned"] != nil)
    #expect(searchObject["next_cursor"] == .null)
    #expect(searchObject["total_matching"] == .null)
    let searchedEvents = try #require(searchObject["events"]?.arrayValue)
    let searchedEvent = try #require(
      searchedEvents.first { $0.objectValue?["id"]?.stringValue == eventID }?.objectValue)
    let searchedAttendees = try #require(searchedEvent["attendees"]?.arrayValue)
    let fencedAttendeeEmail: String = SecurityFencing.fence("alice@example.com")
    #expect(searchedAttendees.first?.objectValue?["email"]?.stringValue == fencedAttendeeEmail)
    let fencedAttendeeName: String = SecurityFencing.fence("Alice")
    #expect(searchedAttendees.first?.objectValue?["name"]?.stringValue == fencedAttendeeName)

    let timeline = try await mcpRegistryCall(
      fixture.registry,
      tool: "get_calendar_timeline",
      arguments: [
        "from": .string("2026-06-09"),
        "to": .string("2026-06-09"),
        "shape": .string("full"),
      ])
    #expect(timeline.isError != true)
    let timelineEvents = try #require(timeline.structuredContent?.objectValue?["events"]?.arrayValue)
    let timelineEvent = try #require(
      timelineEvents.first { $0.objectValue?["id"]?.stringValue == eventID }?.objectValue)
    let timelineAttendees = try #require(timelineEvent["attendees"]?.arrayValue)
    let fencedTimelineEmail: String = SecurityFencing.fence("alice@example.com")
    #expect(timelineAttendees.first?.objectValue?["email"]?.stringValue == fencedTimelineEmail)
  }

  @Test("create_calendar_event accepts a name-only (empty-email) attendee")
  func createCalendarEventAcceptsNameOnlyAttendee() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let created = try await mcpRegistryCall(
      fixture.registry,
      tool: "create_calendar_event",
      arguments: [
        "title": .string("Name-only attendee planning"),
        "start_date": .string("2026-06-09"),
        "start_time": .string("08:00"),
        "end_time": .string("08:30"),
        "attendees": .array([
          .object(["name": .string("Bob")])
        ]),
      ])
    #expect(created.isError != true)
    let attendees = try #require(
      created.structuredContent?.objectValue?["attendees"]?.arrayValue)
    let attendee = try #require(attendees.first?.objectValue)
    let fencedName: String = SecurityFencing.fence("Bob")
    #expect(attendee["name"]?.stringValue == fencedName)
    #expect(attendee["email"]?.stringValue == "")
  }

  @Test("create_calendar_event rejects a fully-empty attendee (no email, no name)")
  func createCalendarEventRejectsFullyEmptyAttendee() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let created = try await mcpRegistryCall(
      fixture.registry,
      tool: "create_calendar_event",
      arguments: [
        "title": .string("Empty attendee planning"),
        "start_date": .string("2026-06-09"),
        "start_time": .string("08:00"),
        "end_time": .string("08:30"),
        "attendees": .array([.object([:])]),
      ])
    #expect(created.isError == true)
  }

  @Test("update_calendar_event accepts a name-only (empty-email) attendee")
  func updateCalendarEventAcceptsNameOnlyAttendee() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let created = try await mcpRegistryCall(
      fixture.registry,
      tool: "create_calendar_event",
      arguments: [
        "title": .string("Update target planning"),
        "start_date": .string("2026-06-09"),
        "start_time": .string("08:00"),
        "end_time": .string("08:30"),
      ])
    let eventID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let updated = try await mcpRegistryCall(
      fixture.registry,
      tool: "update_calendar_event",
      arguments: [
        "event_id": .string(eventID),
        "attendees": .array([
          .object(["name": .string("Carol")])
        ]),
      ])
    #expect(updated.isError != true)
    let attendees = try #require(
      updated.structuredContent?.objectValue?["attendees"]?.arrayValue)
    let attendee = try #require(attendees.first?.objectValue)
    let fencedName: String = SecurityFencing.fence("Carol")
    #expect(attendee["name"]?.stringValue == fencedName)
    #expect(attendee["email"]?.stringValue == "")
  }

  @Test("MCP list writes persist through the on-disk Swift core bridge")
  func listWritePersistsThroughReopenedBridge() async throws {
    let initial = mcpOnDiskRegistry()
    defer { initial.cleanup() }

    let created = try await mcpRegistryCall(
      initial.registry,
      tool: "create_list",
      arguments: [
        "name": .string("On-disk planning"),
        "description": .string("Created through the Swift MCP host"),
      ])
    #expect(created.isError != true)
    let listID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let updated = try await mcpRegistryCall(
      initial.registry,
      tool: "update_list",
      arguments: [
        "id": .string(listID),
        "name": .string("On-disk planning updated"),
        "description": .string("Updated through the Swift MCP host"),
        "color": .string("#0A84FF"),
        "icon": .string("calendar"),
      ])
    #expect(updated.isError != true)
    let fencedUpdatedListName: String = SecurityFencing.fence("On-disk planning updated")
    #expect(updated.structuredContent?.objectValue?["name"]?.stringValue == fencedUpdatedListName)

    let reopened = mcpOnDiskRegistry(dbPath: initial.dbPath)
    let fetched = try await mcpRegistryCall(
      reopened.registry,
      tool: "get_list",
      arguments: ["id": .string(listID)])
    #expect(fetched.isError != true)
    let fetchedList = try #require(fetched.structuredContent?.objectValue)
    #expect(fetchedList["id"]?.stringValue == listID)
    let fencedListName: String = SecurityFencing.fence("On-disk planning updated")
    let fencedListDescription: String = SecurityFencing.fence("Updated through the Swift MCP host")
    #expect(fetchedList["name"]?.stringValue == fencedListName)
    #expect(fetchedList["description"]?.stringValue == fencedListDescription)
    #expect(fetchedList["color"]?.stringValue == "#0A84FF")
    #expect(fetchedList["icon"]?.stringValue == "calendar")

    let health = try await mcpRegistryCall(reopened.registry, tool: "get_list_health_snapshot")
    #expect(health.isError != true)
    let healthLists = try #require(health.structuredContent?.objectValue?["lists"]?.arrayValue)
    #expect(healthLists.contains { $0.objectValue?["id"]?.stringValue == listID })

    let deleted = try await mcpRegistryCall(
      reopened.registry,
      tool: "delete_list",
      arguments: ["id": .string(listID)])
    #expect(deleted.isError != true)
    #expect(deleted.structuredContent?.objectValue?["deleted"]?.boolValue == true)
    #expect(deleted.structuredContent?.objectValue?["id"]?.stringValue == listID)
    #expect(deleted.structuredContent?.objectValue?["deleted_list_id"] == nil)
    #expect(
      deleted.structuredContent?.objectValue?["previous"]?.objectValue?["id"]?.stringValue == listID)

    let filteredDeleteChangelog = try await mcpRegistryCall(
      reopened.registry,
      tool: "get_ai_changelog",
      arguments: [
        "limit": .int(5),
        "entity_type": .string("list"),
        "operation": .string("delete"),
        "entity_id": .string(listID),
      ])
    #expect(filteredDeleteChangelog.isError != true)
    let filteredEntries = try #require(
      filteredDeleteChangelog.structuredContent?.objectValue?["entries"]?.arrayValue)
    #expect(filteredEntries.count == 1)
    #expect(filteredEntries.first?.objectValue?["entity_id"]?.stringValue == listID)

    let changelog = try await mcpRegistryCall(
      reopened.registry,
      tool: "get_ai_changelog",
      arguments: ["limit": .int(20)])
    let entries = try #require(changelog.structuredContent?.objectValue?["entries"]?.arrayValue)
    #expect(entries.contains { entry in
      let object = entry.objectValue
      return object?["entity_type"]?.stringValue == "list"
        && object?["operation"]?.stringValue == "upsert"
        && object?["summary"]?.stringValue?.contains("On-disk planning") == true
    })
    #expect(entries.contains { entry in
      let object = entry.objectValue
      return object?["entity_type"]?.stringValue == "list"
        && object?["operation"]?.stringValue == "delete"
        && object?["entity_id"]?.stringValue == listID
    })
  }

  @Test("MCP tag writes persist through the on-disk Swift core bridge")
  func tagWritePersistsThroughReopenedBridge() async throws {
    let initial = mcpOnDiskRegistry()
    defer { initial.cleanup() }

    let created = try await mcpRegistryCall(
      initial.registry,
      tool: "create_task",
      arguments: [
        "title": .string("On-disk tagged task"),
        "notes": .string("Created for tag bridge coverage"),
      ])
    #expect(created.isError != true)
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let tagged = try await mcpRegistryCall(
      initial.registry,
      tool: "update_task",
      arguments: [
        "id": .string(taskID),
        "title": .string("On-disk tagged task"),
        "notes": .string("Created for tag bridge coverage"),
        "tags_set": .array([.string("swift-core"), .string("mcp")]),
      ])
    #expect(tagged.isError != true)
    let fencedSwiftCoreTag: String = SecurityFencing.fence("swift-core")
    let fencedMCPTag: String = SecurityFencing.fence("mcp")
    #expect(
      tagged.structuredContent?.objectValue?["tags"]?.arrayValue?.compactMap(\.stringValue)
        .contains(fencedSwiftCoreTag) == true)

    let reopened = mcpOnDiskRegistry(dbPath: initial.dbPath)
    let listed = try await mcpRegistryCall(reopened.registry, tool: "list_all_tags")
    #expect(listed.isError != true)
    let tagNames = try #require(listed.structuredContent?.objectValue?["tags"]?.arrayValue)
      .compactMap(\.stringValue)
    #expect(tagNames.contains(fencedSwiftCoreTag))
    #expect(tagNames.contains(fencedMCPTag))

    let renamed = try await mcpRegistryCall(
      reopened.registry,
      tool: "rename_tag",
      arguments: [
        "old_name": .string("swift-core"),
        "new_name": .string("swift-core-renamed"),
      ])
    #expect(renamed.isError != true)
    #expect(renamed.structuredContent?.objectValue?["renamed"]?.boolValue == true)

    let taggedTasks = try await mcpRegistryCall(
      reopened.registry,
      tool: "list_tasks",
      arguments: [
        "status": .string("all"),
        "tags": .array([.string("swift-core-renamed")]),
      ])
    #expect(taggedTasks.isError != true)
    let tasks = try #require(taggedTasks.structuredContent?.objectValue?["tasks"]?.arrayValue)
    let task = try #require(tasks.first { $0.objectValue?["id"]?.stringValue == taskID })
    let fencedTaskTitle: String = SecurityFencing.fence("On-disk tagged task")
    let fencedRenamedTag: String = SecurityFencing.fence("swift-core-renamed")
    #expect(task.objectValue?["title"]?.stringValue == fencedTaskTitle)
    #expect(
      task.objectValue?["tags"]?.arrayValue?.compactMap(\.stringValue)
        .contains(fencedRenamedTag) == true)

    let changelog = try await mcpRegistryCall(
      reopened.registry,
      tool: "get_ai_changelog",
      arguments: [
        "limit": .int(5),
        "entity_type": .string("tag"),
        "operation": .string("rename"),
      ])
    #expect(changelog.isError != true)
    let entries = try #require(changelog.structuredContent?.objectValue?["entries"]?.arrayValue)
    #expect(entries.contains { entry in
      let object = entry.objectValue
      return object?["summary"]?.stringValue?
        .contains("Renamed tag 'swift-core' to 'swift-core-renamed'") == true
    })
  }

  @Test("archive_task unlocks permanent_delete_task through the on-disk MCP bridge")
  func archiveThenPermanentDeleteThroughBridge() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let created = try await mcpRegistryCall(
      fixture.registry, tool: "create_task", arguments: ["title": .string("Archive flow")])
    #expect(created.isError != true)
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    // The two-step guard (#2363): permanent_delete_task is refused while the
    // task is still live, and the refusal is a clean tool error — not a raw
    // JSON-RPC internal error escaping the dispatch boundary.
    let premature = try await mcpRegistryCall(
      fixture.registry, tool: "permanent_delete_task", arguments: ["id": .string(taskID)])
    #expect(premature.isError == true)

    // archive_task moves the task to the Trash and reports archived: true.
    let archived = try await mcpRegistryCall(
      fixture.registry, tool: "archive_task", arguments: ["id": .string(taskID)])
    #expect(archived.isError != true)
    #expect(archived.structuredContent?.objectValue?["archived"]?.boolValue == true)

    // With the archive in place permanent_delete_task now succeeds.
    let deleted = try await mcpRegistryCall(
      fixture.registry, tool: "permanent_delete_task", arguments: ["id": .string(taskID)])
    #expect(deleted.isError != true)
    #expect(deleted.structuredContent?.objectValue?["deleted"]?.boolValue == true)

    // The task is gone.
    let fetched = try await mcpRegistryCall(
      fixture.registry, tool: "get_task", arguments: ["id": .string(taskID)])
    #expect(fetched.isError == true)
  }

  @Test("unarchive_task restores a Trashed task through the on-disk MCP bridge")
  func unarchiveRestoresThroughBridge() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let created = try await mcpRegistryCall(
      fixture.registry, tool: "create_task", arguments: ["title": .string("Restore flow")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    _ = try await mcpRegistryCall(
      fixture.registry, tool: "archive_task", arguments: ["id": .string(taskID)])
    let restored = try await mcpRegistryCall(
      fixture.registry, tool: "unarchive_task", arguments: ["id": .string(taskID)])
    #expect(restored.isError != true)
    #expect(restored.structuredContent?.objectValue?["archived"]?.boolValue == false)

    // Back in the live set: permanent_delete_task is refused again.
    let premature = try await mcpRegistryCall(
      fixture.registry, tool: "permanent_delete_task", arguments: ["id": .string(taskID)])
    #expect(premature.isError == true)
  }

  @Test("delete_list hard-blocks on completed history; archive_list retires it through the on-disk MCP bridge")
  func archiveListRetiresWithHistoryThroughBridge() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let createdList = try await mcpRegistryCall(
      fixture.registry, tool: "create_list", arguments: ["name": .string("Company A")])
    let listID = try #require(createdList.structuredContent?.objectValue?["id"]?.stringValue)

    let createdTask = try await mcpRegistryCall(
      fixture.registry, tool: "create_task", arguments: ["title": .string("Ship v1")])
    let taskID = try #require(createdTask.structuredContent?.objectValue?["id"]?.stringValue)
    _ = try await mcpRegistryCall(
      fixture.registry, tool: "move_task_to_list",
      arguments: ["id": .string(taskID), "list_id": .string(listID)])
    _ = try await mcpRegistryCall(
      fixture.registry, tool: "complete_task", arguments: ["id": .string(taskID)])

    // Completed history still counts as assigned: delete is hard-blocked.
    let blocked = try await mcpRegistryCall(
      fixture.registry, tool: "delete_list", arguments: ["id": .string(listID)])
    #expect(blocked.isError == true)

    // Archiving retires the list while keeping it and its task.
    let archived = try await mcpRegistryCall(
      fixture.registry, tool: "archive_list", arguments: ["id": .string(listID)])
    #expect(archived.isError != true)
    #expect(archived.structuredContent?.objectValue?["archived"]?.boolValue == true)

    // The archived list drops out of the default get_lists set.
    let activeLists = try await mcpRegistryCall(fixture.registry, tool: "get_lists")
    let activeIDs = (activeLists.structuredContent?.objectValue?["lists"]?.arrayValue ?? [])
      .compactMap { $0.objectValue?["id"]?.stringValue }
    #expect(!activeIDs.contains(listID))

    // include_archived surfaces it again, flagged archived.
    let allLists = try await mcpRegistryCall(
      fixture.registry, tool: "get_lists", arguments: ["include_archived": .bool(true)])
    let archivedEntry = (allLists.structuredContent?.objectValue?["lists"]?.arrayValue ?? [])
      .first { $0.objectValue?["id"]?.stringValue == listID }
    #expect(archivedEntry?.objectValue?["archived"]?.boolValue == true)

    // Unarchiving restores it to the active set.
    let unarchived = try await mcpRegistryCall(
      fixture.registry, tool: "unarchive_list", arguments: ["id": .string(listID)])
    #expect(unarchived.isError != true)
    let restoredLists = try await mcpRegistryCall(fixture.registry, tool: "get_lists")
    let restoredIDs = (restoredLists.structuredContent?.objectValue?["lists"]?.arrayValue ?? [])
      .compactMap { $0.objectValue?["id"]?.stringValue }
    #expect(restoredIDs.contains(listID))
  }

  @Test("get_recent_logs returns a real merged stream through the on-disk bridge")
  func recentLogsMergedStreamThroughBridge() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    // Seed writes so both ai_changelog and sync_outbox have rows to merge.
    let seed = SwiftLorvexCoreService(databasePath: fixture.dbPath)
    // `ai_changelog` is the assistant-activity surface; seed under the assistant
    // binding (as the MCP host does in production) so these writes land there for
    // the merge instead of defaulting to `user`, which the surface filters out.
    try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.assistant
    ) {
      _ = try await seed.createTask(title: "Recent logs A", notes: "")
      _ = try await seed.createTask(title: "Recent logs B", notes: "")
    }

    let result = try await mcpRegistryCall(
      fixture.registry, tool: "get_recent_logs", arguments: ["include_details": .bool(true)])
    #expect(result.isError != true)
    let object = try #require(result.structuredContent?.objectValue)
    let entries = try #require(object["entries"]?.arrayValue)
    // Previously always empty regardless of real data.
    #expect(!entries.isEmpty)
    let sources = Set(entries.compactMap { $0.objectValue?["source"]?.stringValue })
    #expect(sources.contains("ai_changelog"))
    #expect(sources.contains("sync_outbox"))
    // include_details=true surfaces the per-entry details key.
    #expect(entries.allSatisfy { $0.objectValue?.keys.contains("details") == true })

    // Source filter narrows the stream.
    let filtered = try await mcpRegistryCall(
      fixture.registry, tool: "get_recent_logs", arguments: ["source": .string("sync_outbox")])
    #expect(filtered.isError != true)
    let filteredEntries = try #require(filtered.structuredContent?.objectValue?["entries"]?.arrayValue)
    #expect(!filteredEntries.isEmpty)
    #expect(filteredEntries.allSatisfy { $0.objectValue?["source"]?.stringValue == "sync_outbox" })
  }

  @Test("get_guide reports real memory and preference state through the on-disk bridge")
  func guideReportsRealStateThroughBridge() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let seed = SwiftLorvexCoreService(databasePath: fixture.dbPath)
    _ = try await seed.upsertMemory(key: "guide_ctx", content: "context body")
    _ = try await seed.setPreference(
      key: "working_hours", value: "{\"start\":\"09:00\",\"end\":\"17:00\"}")

    let result = try await mcpRegistryCall(fixture.registry, tool: "get_guide")
    #expect(result.isError != true)
    let state = try #require(result.structuredContent?.objectValue?["state"]?.objectValue)
    // Previously hardcoded to 0 / [] regardless of the real store.
    #expect(state["memory_count"]?.intValue == 1)
    let prefs = try #require(state["configured_preferences"]?.arrayValue)
      .compactMap(\.stringValue)
    #expect(prefs.contains("working_hours"))
  }

  @Test("batch task mutations return every changed task, enriched in-transaction")
  func batchMutationsReturnEnrichedChangedTasksThroughBridge() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let first = try await mcpRegistryCall(
      fixture.registry, tool: "create_task", arguments: ["title": .string("Batch A")])
    let firstID = try #require(first.structuredContent?.objectValue?["id"]?.stringValue)
    let second = try await mcpRegistryCall(
      fixture.registry, tool: "create_task", arguments: ["title": .string("Batch B")])
    let secondID = try #require(second.structuredContent?.objectValue?["id"]?.stringValue)

    // A genuinely-missing id is reported in `skipped`, never silently dropped;
    // the two real tasks come back in `results` with completed status — the
    // enriched values captured inside the write transaction, not re-read after.
    let completed = try await mcpRegistryCall(
      fixture.registry, tool: "batch_complete_tasks",
      arguments: ["task_ids": .array([.string(firstID), .string(secondID), .string("missing-id")])])
    #expect(completed.isError != true)
    let completedObj = try #require(completed.structuredContent?.objectValue)
    let completedResults = try #require(completedObj["results"]?.arrayValue)
    #expect(completedObj["count"]?.intValue == completedResults.count)
    #expect(completedResults.count == 2)
    let completedIDs = Set(completedResults.compactMap { $0.objectValue?["id"]?.stringValue })
    #expect(completedIDs == [firstID, secondID])
    #expect(completedResults.allSatisfy { $0.objectValue?["status"]?.stringValue == "completed" })
    let skippedIDs = (completedObj["skipped"]?.arrayValue ?? [])
      .compactMap { $0.objectValue?["id"]?.stringValue }
    #expect(skippedIDs == ["missing-id"])

    // batch_cancel_tasks_in_list returns the full cancelled tasks captured in the
    // same transaction, not ids re-read afterward.
    let list = try await mcpRegistryCall(
      fixture.registry, tool: "create_list", arguments: ["name": .string("Cancel list")])
    let listID = try #require(list.structuredContent?.objectValue?["id"]?.stringValue)
    let inList = try await mcpRegistryCall(
      fixture.registry, tool: "create_task",
      arguments: ["title": .string("In list"), "list_id": .string(listID)])
    let inListID = try #require(inList.structuredContent?.objectValue?["id"]?.stringValue)

    let cancelled = try await mcpRegistryCall(
      fixture.registry, tool: "batch_cancel_tasks_in_list",
      arguments: ["list_id": .string(listID)])
    #expect(cancelled.isError != true)
    let cancelledResults = try #require(cancelled.structuredContent?.objectValue?["results"]?.arrayValue)
    #expect(cancelledResults.count == 1)
    #expect(cancelledResults.first?.objectValue?["id"]?.stringValue == inListID)
    #expect(cancelledResults.first?.objectValue?["status"]?.stringValue == "cancelled")
  }

  @Test("single status tools return the mutated task without a post-commit re-read")
  func singleStatusToolsReturnEnrichedTaskThroughBridge() async throws {
    let fixture = mcpOnDiskRegistry()
    defer { fixture.cleanup() }

    let created = try await mcpRegistryCall(
      fixture.registry, tool: "create_task", arguments: ["title": .string("Status target")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let completed = try await mcpRegistryCall(
      fixture.registry, tool: "complete_task", arguments: ["id": .string(taskID)])
    #expect(completed.isError != true)
    #expect(completed.structuredContent?.objectValue?["id"]?.stringValue == taskID)
    #expect(completed.structuredContent?.objectValue?["status"]?.stringValue == "completed")

    let reopened = try await mcpRegistryCall(
      fixture.registry, tool: "reopen_task", arguments: ["id": .string(taskID)])
    #expect(reopened.structuredContent?.objectValue?["status"]?.stringValue == "open")

    let deferred = try await mcpRegistryCall(
      fixture.registry, tool: "defer_task",
      arguments: ["id": .string(taskID), "until_date": .string("2027-03-01")])
    #expect(deferred.isError != true)
    #expect(deferred.structuredContent?.objectValue?["planned_date"]?.stringValue == "2027-03-01")

    let cancelled = try await mcpRegistryCall(
      fixture.registry, tool: "cancel_task", arguments: ["id": .string(taskID)])
    #expect(cancelled.structuredContent?.objectValue?["status"]?.stringValue == "cancelled")
  }

}
