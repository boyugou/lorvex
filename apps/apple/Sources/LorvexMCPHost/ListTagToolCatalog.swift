import MCP

// MCP id-argument naming rule: a tool's own CRUD/lifecycle target is `id`; a
// reference to a foreign or parent entity (a sub-resource, relationship, or
// query tool) is `<entity>_id`. This file shows both sides: `update_list` /
// `delete_list` act on the list itself and take `id`, while `set_list_ai_notes`
// maintains a sub-resource of a list and so takes `list_id` (matching the
// parallel `set_task_ai_notes`, which takes `task_id`). New tools must follow
// this convention.
extension ListHabitToolCatalog {
  static let updateListTool = Tool(
    name: "update_list",
    title: "Update List",
    description: "Update a Lorvex list's name, description, color, or icon. Use set_list_ai_notes for assistant-maintained list context. Returns the full updated list object.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "id": .object(["type": .string("string"), "description": .string("List ID")]),
        "name": .object(["type": .string("string"), "description": .string("New list name")]),
        "description": .object([
          "type": .string("string"),
          "description": .string("List description"),
        ]),
        "color": .object([
          "type": .string("string"),
          "description": .string("#RRGGBB hex accent (e.g. '#22C55E')"),
        ]),
        "icon": .object([
          "type": .string("string"),
          "description": .string("SF Symbol name (e.g. 'briefcase', 'house')"),
        ]),
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false
    )
  )

  // List AI-notes are an AI-only surface by design: this tool is their sole
  // read/write path (empty `notes` clears the block). Unlike task AI-notes,
  // which macOS renders read-only with a clear affordance, list AI-notes have
  // no view/clear UI — they are internal assistant context, not a user surface.
  static let setListAINotesTool = Tool(
    name: "set_list_ai_notes",
    title: "Set List AI Context",
    description: "Replace the assistant-maintained context block for one list without changing the canonical list description. Use this for scope guidance, caveats, operating instructions, or short reasoning a future assistant should preserve. Pass an empty notes string to clear the block. Returns the full updated list object.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "list_id": .object([
          "type": .string("string"),
          "description": .string("List id"),
        ]),
        "notes": .object([
          "type": .string("string"),
          "description": .string("Current assistant context for this list; empty clears it"),
        ]),
      ]),
      "required": .array([.string("list_id"), .string("notes")]),
    ]),
    annotations: .init(
      readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false
    )
  )

  static let deleteListTool = Tool(
    name: "delete_list",
    title: "Delete List",
    description: "Permanently delete a Lorvex list. Fails if any tasks are still assigned — including completed or cancelled ones — so move or delete those tasks first. To retire a finished project while keeping its task history under the list's name, use archive_list instead. The last remaining list cannot be deleted. Returns {deleted, id, previous} where previous is the removed list object (null on a no-op).",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "id": .object(["type": .string("string"), "description": .string("List ID")])
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false
    )
  )

  static let archiveListTool = Tool(
    name: "archive_list",
    title: "Archive List",
    description: "Archive a Lorvex list, retiring it from the active set while keeping the list and all its tasks — including completed and cancelled history — under its name. Use this instead of delete_list when a project is finished but its records should be preserved. Reversible via unarchive_list. Returns the full updated list object.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "id": .object(["type": .string("string"), "description": .string("List ID")])
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false
    )
  )

  static let unarchiveListTool = Tool(
    name: "unarchive_list",
    title: "Unarchive List",
    description: "Restore a previously archived Lorvex list back to the active set, with all of its tasks intact. Returns the full updated list object.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "id": .object(["type": .string("string"), "description": .string("List ID")])
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false
    )
  )

  static let getListTool = Tool(
    name: "get_list",
    title: "Get List",
    description: "Read a single Lorvex list by ID with task counts.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "id": .object(["type": .string("string"), "description": .string("List ID")])
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let getListHealthSnapshotTool = Tool(
    name: "get_list_health_snapshot",
    title: "Get List Health Snapshot",
    description: "Return task health metrics per list: open count, overdue count, and due-today count. Use during weekly review to identify stalled or overloaded lists at a glance, or before reorganizing tasks to understand which lists need attention. Returns an array sorted by open count descending.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([:]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let reorderListsTool = Tool(
    name: "reorder_lists",
    title: "Reorder Lists",
    description: "Set the manual display order of the active lists catalog. Supply the active list ids in the desired order; each listed list's position is rewritten to its index, so the order converges across devices as an ordinary synced field. Ids omitted from the array keep their current position and ids that no longer resolve are skipped. This never creates, deletes, or archives a list — use create_list / delete_list / archive_list for that. Returns the full refreshed lists catalog in the new order.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "list_ids": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
          "description": .string("Active list ids in the desired display order"),
        ]),
      ]),
      "required": .array([.string("list_ids")]),
    ]),
    annotations: .init(
      readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false
    )
  )

  static let listAllTagsTool = Tool(
    name: "list_all_tags",
    title: "List All Tags",
    description: "Return every tag attached to non-archived tasks.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([:]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let renameTagTool = Tool(
    name: "rename_tag",
    title: "Rename Tag",
    description: "Rename a tag across all tasks. A case-only change (same tag, different casing) is allowed. Renaming onto a name that already exists as a different tag is rejected — re-tag those tasks onto the existing tag instead. Returns the new name and how many tasks now carry it.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "old_name": .object([
          "type": .string("string"), "description": .string("Existing tag name"),
        ]),
        "new_name": .object([
          "type": .string("string"), "description": .string("New tag name"),
        ]),
      ]),
      "required": .array([.string("old_name"), .string("new_name")]),
    ]),
    annotations: .init(
      readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false
    )
  )

  static let deleteTagTool = Tool(
    name: "delete_tag",
    title: "Delete Tag",
    description: "Permanently delete a tag and remove it from every task that carries it. The tasks themselves are kept — only the tag and its task links are removed. To fold a tag's tasks onto another tag instead of dropping them, re-tag those tasks onto the target tag first (via update_task), then delete this one. Returns {deleted, id, previous, tag, tasks_updated, task_ids} where tag is the deleted tag name, tasks_updated is how many tasks it was removed from, task_ids lists those tasks, and previous is null (a tag is not a stored object).",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "name": .object([
          "type": .string("string"), "description": .string("Existing tag name"),
        ]),
      ]),
      "required": .array([.string("name")]),
    ]),
    annotations: .init(
      readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false
    )
  )

  static let mergeTagsTool = Tool(
    name: "merge_tags",
    title: "Merge Tags",
    description: "Merge one tag into another in a single atomic operation: re-tag every task carrying the source tag onto the target tag (skipping tasks that already carry the target, so no task ends up double-tagged), then delete the source tag. Both tags must already exist and be different — to give a tag a brand-new name use rename_tag instead. Returns {merged, source, target, tasks_updated, tasks_moved, tasks_deduped, task_ids} where tasks_updated is how many tasks carried the source tag, tasks_moved is how many gained the target tag, tasks_deduped is how many already carried it, and task_ids lists those tasks.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "source": .object([
          "type": .string("string"), "description": .string("Tag to merge away (deleted afterward)"),
        ]),
        "target": .object([
          "type": .string("string"), "description": .string("Surviving tag its tasks are folded onto"),
        ]),
      ]),
      "required": .array([.string("source"), .string("target")]),
    ]),
    annotations: .init(
      readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false
    )
  )

}
