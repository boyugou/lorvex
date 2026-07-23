import MCP

extension TaskMutationToolCatalog {
  static let batchDeferTasksTool = Tool(
    name: "batch_defer_tasks",
    title: "Batch Defer Tasks",
    description:
      "Set planned_date on multiple tasks to the same future day. Use during morning planning or weekly review when pushing several tasks to a later date. Reschedules the planned work day and records the push; to merely hide a task until a date without rescheduling, set available_from instead (that does not count as a deferral). Increments defer_count per task. Returns {results, count, skipped, defer_note} — results holds the updated tasks, skipped is [{id, reason}] for ids that could not be deferred.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "task_ids": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
        ]),
        "until_date": .object([
          "type": .string("string"),
          "description": .string("Absolute planned date target in YYYY-MM-DD"),
        ]),
        "reason": .object([
          "type": .string("string"),
          "description": .string(
            "Optional free-text reason. Echoed back as defer_note and persisted onto this batch's changelog entry, surfaced read-only in each deferred task's get_task defer_history. It is not written to ai_notes; use set_task_ai_notes when the task's assistant context should change."),
        ]),
        "structured_reason": .object([
          "type": .string("string"),
          "enum": .array([
            .string("not_today"), .string("blocked"), .string("low_energy"),
            .string("needs_breakdown"), .string("needs_info"),
          ]),
          "description": .string(
            "Optional category: not_today, blocked, low_energy, needs_breakdown, or needs_info. Recorded in each task's last_defer_reason field for pattern tracking."),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("task_ids"), .string("until_date")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let moveTaskToListTool = Tool(
    name: "move_task_to_list",
    title: "Move Task To List",
    description: "Move one task to a different list. Use when organizing tasks after capture or when a task's scope changes. Returns the updated task with new list_id.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "id": .object([
          "type": .string("string"),
          "description": .string("Task id"),
        ]),
        "list_id": .object([
          "type": .string("string"),
          "description": .string("Target list id"),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("id"), .string("list_id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let batchCancelTasksInListTool = Tool(
    name: "batch_cancel_tasks_in_list",
    title: "Batch Cancel Tasks In List",
    description: "Cancel all open, in-progress, and someday tasks in a list at once. Use when closing out a project, archiving a list, or clearing a backlog. Narrower than batch_cancel_tasks (by ID) — the list_id + statuses filter selects the candidates automatically. Pass cancel_series=true to stop any recurring series. Defaults to cancelling open, in_progress, and someday tasks; pass statuses=[\"open\"] to target only not-yet-started tasks. Returns {results, count, list_id, skipped} where results is the cancelled task objects.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "list_id": .object([
          "type": .string("string"),
          "description": .string("List to cancel tasks in"),
        ]),
        "statuses": .object([
          "type": .string("array"),
          "items": .object([
            "type": .string("string"),
            "enum": .array([.string("open"), .string("in_progress"), .string("someday")]),
          ]),
          "description": .string(
            "Status filter. Defaults to [open, in_progress, someday]. Pass [open] to target only not-yet-started tasks."),
        ]),
        "cancel_series": .object([
          "type": .string("boolean"),
          "description": .string(
            "When true, cancels the entire recurring series for recurring tasks. Defaults to false."),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("list_id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    )
  )
}
