import MCP
import Testing

@testable import LorvexMCPHost

@Suite("MCP Tool Registry — tag tools")
struct TagToolTests {

  @Test("tag tools return shared task shape after rename")
  func tagToolsSharedTaskShape() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry,
      tool: "create_task",
      arguments: [
        "title": .string("Tagged preview task"),
        "notes": .string("Preview tag smoke"),
      ]
    )
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)

    let tagged = try await mcpRegistryCall(
      registry,
      tool: "update_task",
      arguments: [
        "id": .string(taskID),
        "title": .string("Tagged preview task"),
        "notes": .string("Preview tag smoke"),
        "tags_set": .array([.string("preview"), .string("apple")]),
      ]
    )
    #expect(tagged.isError != true)

    let listed = try await mcpRegistryCall(registry, tool: "list_all_tags")
    #expect(listed.isError != true)
    let tagNames =
      listed.structuredContent?.objectValue?["tags"]?.arrayValue?.compactMap(\.stringValue) ?? []
    let fencedPreviewTag: String = SecurityFencing.fence("preview")
    #expect(tagNames.contains(fencedPreviewTag))

    let renamed = try await mcpRegistryCall(
      registry,
      tool: "rename_tag",
      arguments: ["old_name": .string("preview"), "new_name": .string("swift-preview")]
    )
    #expect(renamed.isError != true)
    #expect(renamed.structuredContent?.objectValue?["renamed"]?.boolValue == true)
    let fencedOldName: String = SecurityFencing.fence("preview" as String)
    let fencedNewName: String = SecurityFencing.fence("swift-preview" as String)
    #expect(
      renamed.structuredContent?.objectValue?["old_name"]?.stringValue
        == fencedOldName)
    #expect(
      renamed.structuredContent?.objectValue?["new_name"]?.stringValue
        == fencedNewName)

    let result = try await mcpRegistryCall(
      registry,
      tool: "list_tasks",
      arguments: [
        "status": .string("all"),
        "tags": .array([.string("swift-preview")]),
      ]
    )
    #expect(result.isError != true)
    let task = try #require(result.structuredContent?.objectValue?["tasks"]?.arrayValue?.first)
    #expect(task.objectValue?["id"]?.stringValue == taskID)
    let fencedTitle: String = SecurityFencing.fence("Tagged preview task")
    #expect(task.objectValue?["title"]?.stringValue == fencedTitle)
    #expect(task.objectValue?["priority"]?.intValue != nil)
    #expect(task.objectValue?["priority_label"]?.stringValue != nil)
    #expect(task.objectValue?["list_id"] != nil)
    let fencedRenamedTag: String = SecurityFencing.fence("swift-preview")
    #expect(
      task.objectValue?["tags"]?.arrayValue?.compactMap(\.stringValue).contains(fencedRenamedTag)
        == true)
  }

  @Test("delete_tag removes the tag and fences its name in the response")
  func deleteTagTool() async throws {
    let registry = try mcpInMemoryRegistry()
    let created = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string("Delete-tag task"), "notes": .string("")])
    let taskID = try #require(created.structuredContent?.objectValue?["id"]?.stringValue)
    _ = try await mcpRegistryCall(
      registry, tool: "update_task",
      arguments: [
        "id": .string(taskID), "title": .string("Delete-tag task"), "notes": .string(""),
        "tags_set": .array([.string("temp"), .string("keep")]),
      ])

    let deleted = try await mcpRegistryCall(
      registry, tool: "delete_tag", arguments: ["name": .string("temp")])
    #expect(deleted.isError != true)
    #expect(deleted.structuredContent?.objectValue?["deleted"]?.boolValue == true)
    #expect(deleted.structuredContent?.objectValue?["tasks_updated"]?.intValue == 1)
    let fencedTemp: String = SecurityFencing.fence("temp")
    #expect(deleted.structuredContent?.objectValue?["tag"]?.stringValue == fencedTemp)
    // Uniform delete-return trio: id mirrors the fenced tag name; a tag has no
    // stored object, so previous is null.
    #expect(deleted.structuredContent?.objectValue?["id"]?.stringValue == fencedTemp)
    #expect(deleted.structuredContent?.objectValue?["previous"] == .null)
    // task_ids carry the affected task and stay unfenced (Lorvex-controlled IDs).
    #expect(
      deleted.structuredContent?.objectValue?["task_ids"]?.arrayValue?
        .compactMap(\.stringValue) == [taskID])

    let tags = try await mcpRegistryCall(registry, tool: "list_all_tags")
    let names =
      tags.structuredContent?.objectValue?["tags"]?.arrayValue?.compactMap(\.stringValue) ?? []
    #expect(!names.contains(fencedTemp))
    #expect(names.contains(SecurityFencing.fence("keep")))
  }

  @Test("merge_tags folds the source onto the target, dedupes, and deletes the source")
  func mergeTagsTool() async throws {
    let registry = try mcpInMemoryRegistry()

    // taskA carries only the source tag; taskB carries source + target, so the
    // merge re-points taskA (moved) and dedupes taskB (already tagged).
    let createdA = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string("Merge task A"), "notes": .string("")])
    let taskA = try #require(createdA.structuredContent?.objectValue?["id"]?.stringValue)
    _ = try await mcpRegistryCall(
      registry, tool: "update_task",
      arguments: [
        "id": .string(taskA), "title": .string("Merge task A"), "notes": .string(""),
        "tags_set": .array([.string("temp")]),
      ])

    let createdB = try await mcpRegistryCall(
      registry, tool: "create_task",
      arguments: ["title": .string("Merge task B"), "notes": .string("")])
    let taskB = try #require(createdB.structuredContent?.objectValue?["id"]?.stringValue)
    _ = try await mcpRegistryCall(
      registry, tool: "update_task",
      arguments: [
        "id": .string(taskB), "title": .string("Merge task B"), "notes": .string(""),
        "tags_set": .array([.string("temp"), .string("keep")]),
      ])

    let merged = try await mcpRegistryCall(
      registry, tool: "merge_tags",
      arguments: ["source": .string("temp"), "target": .string("keep")])
    #expect(merged.isError != true)
    let structured = try #require(merged.structuredContent?.objectValue)
    #expect(structured["merged"]?.boolValue == true)
    // source/target are user-controlled and fenced like rename_tag's names.
    let fencedTemp: String = SecurityFencing.fence("temp")
    let fencedKeep: String = SecurityFencing.fence("keep")
    #expect(structured["source"]?.stringValue == fencedTemp)
    #expect(structured["target"]?.stringValue == fencedKeep)
    #expect(structured["tasks_updated"]?.intValue == 2)
    #expect(structured["tasks_moved"]?.intValue == 1)
    #expect(structured["tasks_deduped"]?.intValue == 1)
    let taskIDs = structured["task_ids"]?.arrayValue?.compactMap(\.stringValue) ?? []
    #expect(Set(taskIDs) == Set([taskA, taskB]))

    // The source tag is gone; the target remains and now carries both tasks.
    let tags = try await mcpRegistryCall(registry, tool: "list_all_tags")
    let names =
      tags.structuredContent?.objectValue?["tags"]?.arrayValue?.compactMap(\.stringValue) ?? []
    #expect(!names.contains(fencedTemp))
    #expect(names.contains(fencedKeep))

    let onTarget = try await mcpRegistryCall(
      registry, tool: "list_tasks",
      arguments: ["status": .string("all"), "tags": .array([.string("keep")])])
    let targetTaskIDs =
      onTarget.structuredContent?.objectValue?["tasks"]?.arrayValue?
      .compactMap { $0.objectValue?["id"]?.stringValue } ?? []
    #expect(Set(targetTaskIDs) == Set([taskA, taskB]))
  }

  @Test("merge_tags requires both source and target")
  func mergeTagsRequiresBoth() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "merge_tags", arguments: ["source": .string("temp")])
    expectMCPStructuredError(result, code: "validation", tool: "merge_tags")
  }
}
