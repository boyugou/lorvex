import MCP

/// Batch lifecycle + body/reminder mutation tools.
/// See `TaskBatchListMutationToolCatalog.swift` for deferral and move-one schemas.
enum TaskBatchOpsToolCatalog {
  private static let taskIDsProperty: Value = .object([
    "type": .string("array"),
    "description": .string("Non-empty list of task ids to act on."),
    "items": .object(["type": .string("string")]),
    "minItems": .int(1),
  ])

  static let batchCompleteTool = Tool(
    name: "batch_complete_tasks",
    title: "Batch Complete Tasks",
    description: "Mark multiple tasks as completed in one call. Use instead of calling complete_task in a loop. Returns {results, count, skipped} where results is the completed task objects and skipped is [{id, reason}] for ids that could not be completed.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "task_ids": taskIDsProperty,
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("task_ids")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let batchReopenTool = Tool(
    name: "batch_reopen_tasks",
    title: "Batch Reopen Tasks",
    description: "Reopen multiple completed or cancelled tasks at once. Clears completed_at, planned_date, last_deferred_at, and defer_count on each. For completed recurring tasks, cancels any auto-spawned successors. Returns {results, count, skipped} where results is the reopened task objects and skipped is [{id, reason}].",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "task_ids": taskIDsProperty,
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("task_ids")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let batchCancelTool = Tool(
    name: "batch_cancel_tasks",
    title: "Batch Cancel Tasks",
    description: "Soft-delete multiple tasks at once (status=cancelled). Skips already-completed or already-cancelled tasks. Pass cancel_series=true to stop any recurring series. Returns {results, count, skipped} where results is the cancelled task objects and skipped is [{id, reason}].",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "task_ids": taskIDsProperty,
        "cancel_series": .object([
          "type": .string("boolean"),
          "description": .string("When true, clear recurrence on cancelled recurring tasks."),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("task_ids")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let batchMoveTool = Tool(
    name: "batch_move_tasks",
    title: "Batch Move Tasks",
    description: "Move multiple tasks to a target list in one call. Use instead of calling move_task_to_list in a loop for reorganization or triage. Returns {results, count, list_id, skipped} where results is the moved task objects and skipped is [{id, reason}].",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "task_ids": taskIDsProperty,
        "list_id": .object([
          "type": .string("string"),
          "description": .string("Destination list id."),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("task_ids"), .string("list_id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let appendBodyTool = Tool(
    name: "append_to_task_body",
    title: "Append To Task Body",
    description: "Append Markdown text to a task's body/notes without replacing existing content. Added after a blank-line separator. Use for observations, context, or quick notes without overwriting existing body content. Prefer set_task_ai_notes for assistant-maintained context that should be visually distinct. Returns the full updated task object.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "task_id": .object([
          "type": .string("string"),
          "description": .string("Task id."),
        ]),
        "text": .object([
          "type": .string("string"),
          "description": .string("Markdown text to append."),
        ]),
      ]),
      "required": .array([.string("task_id"), .string("text")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let setRemindersTool = Tool(
    name: "set_task_reminders",
    title: "Set Task Reminders",
    description: "Replace all pending reminders for a task in one call (atomic: removes existing reminders, adds the new set). Pass an empty array to clear all reminders. Use instead of calling add_task_reminder + remove_task_reminder when setting multiple reminders at once. Returns the full updated task.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "task_id": .object([
          "type": .string("string"),
          "description": .string("Task id."),
        ]),
        "reminders": .object([
          "type": .string("array"),
          "description": .string("RFC 3339 UTC timestamps for each reminder, e.g. 2026-05-23T17:00:00Z."),
          "items": .object(["type": .string("string")]),
        ]),
      ]),
      "required": .array([.string("task_id"), .string("reminders")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )
}
