import Foundation
import MCP

extension ToolRegistry {
  func listAllTagsResult() async throws -> CallTool.Result {
    let tags = try await tagNamesPayload()
    return tagListResult(tags)
  }

  func renameTagResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let oldName = arguments["old_name"]?.stringValue, !oldName.isEmpty,
      let newName = arguments["new_name"]?.stringValue, !newName.isEmpty
    else {
      return Self.errorResult(
        code: "validation", message: "old_name and new_name are required.", toolName: "rename_tag")
    }

    let renamed = try await renameTagPayload(oldName: oldName, newName: newName)
    // Report how many tasks now carry the renamed tag, so the response says
    // something concrete instead of a bare `renamed: true`.
    let tasksUpdated = try await taskCountForTagPayload(tag: newName)

    return CallTool.Result(
      content: [
        .text(
          text: "Renamed tag \(oldName) to \(newName) (\(tasksUpdated) task(s)).",
          annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(.object([
        "renamed": .bool(renamed),
        "old_name": .string(SecurityFencing.fence(oldName)),
        "new_name": .string(SecurityFencing.fence(newName)),
        "tasks_updated": .int(tasksUpdated),
      ])),
      isError: false
    )
  }

  func deleteTagResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let name = arguments["name"]?.stringValue, !name.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "name is required.", toolName: "delete_tag")
    }

    let outcome = try await deleteTagPayload(name: name)

    return CallTool.Result(
      content: [
        .text(
          text: "Deleted tag \(outcome.tag) from \(outcome.tasksUpdated) task(s).",
          annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(.object([
        "deleted": .bool(true),
        // A tag's identity is its name, so `id` mirrors `tag`. Both are
        // user-controlled free text and are fenced like rename_tag's names. A tag
        // is not a stored entity — it is materialized from task associations — so
        // there is no removed object to return: `previous` is null, and the effect
        // is described by `task_ids`/`tasks_updated`. IDs in `task_ids` are
        // Lorvex-controlled and stay unfenced.
        "id": .string(SecurityFencing.fence(outcome.tag)),
        "previous": .null,
        "tag": .string(SecurityFencing.fence(outcome.tag)),
        "tasks_updated": .int(outcome.tasksUpdated),
        "task_ids": .array(outcome.taskIDs.map(Value.string)),
      ])),
      isError: false
    )
  }

  func mergeTagsResult(arguments: [String: Value]) async throws -> CallTool.Result {
    // Tag names are fenced when echoed back in responses (list_all_tags,
    // rename_tag, etc.), so an AI client may pass a fenced value straight back
    // as an argument — unfence so it round-trips to the stored tag name.
    let source = SecurityFencing.unfence(
      try StrictScalarArguments.optionalString(arguments["source"], field: "source") ?? ""
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
    let target = SecurityFencing.unfence(
      try StrictScalarArguments.optionalString(arguments["target"], field: "target") ?? ""
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !source.isEmpty, !target.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "source and target are required.", toolName: "merge_tags")
    }

    let outcome = try await mergeTagsPayload(source: source, target: target)

    return CallTool.Result(
      content: [
        .text(
          text: "Merged tag \(outcome.source) into \(outcome.target) "
            + "(\(outcome.tasksMoved) moved, \(outcome.tasksDeduped) already tagged).",
          annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(.object([
        "merged": .bool(true),
        // source/target are user-controlled free text; fence them like rename_tag's
        // names. The central dispatch fencing does not cover these keys, so fence
        // here. task_ids are Lorvex-controlled IDs and stay unfenced.
        "source": .string(SecurityFencing.fence(outcome.source)),
        "target": .string(SecurityFencing.fence(outcome.target)),
        "tasks_updated": .int(outcome.tasksUpdated),
        "tasks_moved": .int(outcome.tasksMoved),
        "tasks_deduped": .int(outcome.tasksDeduped),
        "task_ids": .array(outcome.taskIDs.map(Value.string)),
      ])),
      isError: false
    )
  }

  private func tagListResult(_ tags: [String]) -> CallTool.Result {
    CallTool.Result(
      content: [.text(text: "\(tags.count) tag(s).", annotations: nil, _meta: nil)],
      // The dispatch layer fences the `tags` array (a userContentArrayKey) centrally.
      structuredContent: Optional.some(.object(["tags": .array(tags.map(Value.string))])),
      isError: false
    )
  }
}
