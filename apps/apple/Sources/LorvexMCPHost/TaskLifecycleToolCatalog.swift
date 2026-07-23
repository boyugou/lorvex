import MCP

extension TaskMutationToolCatalog {
  static let completeTaskTool = Tool(
    name: "complete_task",
    title: "Complete Task",
    description: "Mark a task as completed. For recurring tasks, also spawns the next occurrence in the series. Returns the updated task.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "id": .object([
          "type": .string("string"),
          "description": .string("Task id"),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let cancelTaskTool = Tool(
    name: "cancel_task",
    title: "Cancel Task",
    description: "Soft-delete a task (status=cancelled). For recurring tasks, cancels this occurrence and spawns the next one — the series continues. Prefer cancel_task over update_task for status transitions. Returns the updated task.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "id": .object([
          "type": .string("string"),
          "description": .string("Task id"),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let reopenTaskTool = Tool(
    name: "reopen_task",
    title: "Reopen Task",
    description: "Reopen a completed, cancelled, or someday task (set back to open status). Clears completed_at, planned_date, last_deferred_at, and defer_count. For completed recurring tasks, also cancels any auto-spawned successor to prevent duplicates. Returns the full updated task object.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "id": .object([
          "type": .string("string"),
          "description": .string("Task id"),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let startTaskTool = Tool(
    name: "start_task",
    title: "Start Task",
    description: "Mark a task as in progress (status=in_progress) — the 'started' marker that surfaces it in the Today \"In Progress\" section. Use it when the user resumes or begins active work; pause_task removes the marker. Only an open task can be started (reopen a completed/cancelled/someday task first); calling it on an already-started task is a no-op. Starting a task whose dependencies are unfinished is rejected, naming the blockers. in_progress surfaces everywhere open does; it does not stop reminders or advance recurrence. There is no started_at column — to answer \"how long has this been in progress\", read the timestamp of the most recent 'start' transition in get_ai_changelog. Returns the full updated task object.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "id": .object([
          "type": .string("string"),
          "description": .string("Task id"),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let pauseTaskTool = Tool(
    name: "pause_task",
    title: "Pause Task",
    description: "Remove the in-progress marker (status in_progress → open), the un-start / mis-click recovery. It leaves no residue — planned_date and defer_count are preserved, so start then pause is a metadata no-op. Only an in-progress task can be paused; calling it on an already-open task is a no-op. Pausing does not cancel or defer the task; it stays actionable. Returns the full updated task object.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "id": .object([
          "type": .string("string"),
          "description": .string("Task id"),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let deferTaskTool = Tool(
    name: "defer_task",
    title: "Defer Task",
    description: "Push a task's planned work day to a future date (until_date), leaving status open. Reschedules the planned work day and records the push; to merely hide a task until a date without rescheduling, set available_from instead (that does not count as a deferral). Increments defer_count and, when structured_reason is supplied, records it in the task's last_defer_reason field for pattern tracking. Any free-text reason is persisted onto this defer's changelog entry (read it back via get_task's read-only defer_history), not into ai_notes. Returns the full updated task object, including defer_count, last_defer_reason, and a defer_note echoing the free-text reason.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "id": .object([
          "type": .string("string"),
          "description": .string("Task id"),
        ]),
        "until_date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD date to defer the task to"),
        ]),
        "reason": .object([
          "type": .string("string"),
          "description": .string(
            "Optional free-text reason for this defer. Echoed back as defer_note and persisted onto this defer's changelog entry, surfaced read-only in get_task's defer_history. It is not written to ai_notes; use set_task_ai_notes when the task's assistant context should change."),
        ]),
        "structured_reason": .object([
          "type": .string("string"),
          "enum": .array([
            .string("not_today"), .string("blocked"), .string("low_energy"),
            .string("needs_breakdown"), .string("needs_info"),
          ]),
          "description": .string(
            "Optional structured defer reason. Recorded in the task's last_defer_reason field for pattern tracking."),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("id"), .string("until_date")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let setTaskSomedayTool = Tool(
    name: "set_task_someday",
    title: "Set Task Someday",
    description: "Park a task in the GTD Someday/Maybe bucket (status=someday). Use for low-priority backlog the user wants tracked but not actionable now; the assistant can resurface it when free time appears. The task keeps its list, due date, and other fields — status is orthogonal to list membership. Reopen it later with reopen_task. Returns the full updated task object.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "id": .object([
          "type": .string("string"),
          "description": .string("Task id"),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let permanentDeleteTaskTool = Tool(
    name: "permanent_delete_task",
    title: "Permanent Delete Task",
    description: "Hard-delete a task and all its child rows (reminders, checklist items, tags, dependencies) from the database, emitting a sync tombstone so the deletion propagates to other devices. This is irreversible — unlike cancel_task which sets status=cancelled and preserves the record. Fails unless the task has already been archived with archive_task: this two-step guard ensures a single call can never destroy live data, so archive first, then permanent-delete. Use only when the task should never have existed or must be removed from audit history. Returns {deleted, id, previous} where previous is the removed task object (null on a no-op).",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "id": .object([
          "type": .string("string"),
          "description": .string("Task id to permanently delete"),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: false
    )
  )

  static let archiveTaskTool = Tool(
    name: "archive_task",
    title: "Archive Task",
    description: "Move a task to the Trash (soft delete) by stamping archived_at. The task is hidden from active views but fully preserved and reversible — restore it with unarchive_task. This is the first step of the two-step permanent-delete flow: permanent_delete_task only removes a task that has been archived first, so a single call can never destroy live data. To merely mark work abandoned while keeping it visible, prefer cancel_task. Returns the task with archived: true.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "id": .object([
          "type": .string("string"),
          "description": .string("Task id to move to the Trash"),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let unarchiveTaskTool = Tool(
    name: "unarchive_task",
    title: "Unarchive Task",
    description: "Restore a task from the Trash by clearing archived_at — the inverse of archive_task. The task reappears in active views with its prior content intact. Errors if the task is not currently archived. Returns the task with archived: false.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "id": .object([
          "type": .string("string"),
          "description": .string("Task id to restore from the Trash"),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )
}
