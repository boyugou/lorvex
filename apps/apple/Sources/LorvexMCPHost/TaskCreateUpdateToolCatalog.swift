import MCP

extension TaskMutationToolCatalog {
  static let createTaskTool = Tool(
    name: "create_task",
    title: "Create Task",
    description: "Capture one task. Accepts title plus optional notes, raw_input, list_id, priority, due_date, planned_date, available_from, tags, depends_on, checklist, and estimated_minutes. Prefer this over batch_create_tasks when creating a single task. Returns the created task, including any checklist items created from the checklist array.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "title": .object([
          "type": .string("string"),
          "description": .string("Task title"),
        ]),
        "notes": .object([
          "type": .string("string"),
          "description": .string("Optional task notes"),
        ]),
        "raw_input": .object([
          "type": .string("string"),
          "description": .string(
            "The user's verbatim original capture text, preserved alongside the AI-parsed fields (backs transparent reasoning). Optional."
          ),
        ]),
        "list_id": .object([
          "type": .string("string"),
          "description": .string("Optional destination list id. Defaults to inbox."),
        ]),
        "priority": .object([
          "type": .string("integer"),
          "enum": .array([.int(1), .int(2), .int(3)]),
          "description": .string("Priority: 1 (highest), 2, or 3."),
        ]),
        "estimated_minutes": .object([
          "type": .string("integer"),
          "description": .string("Optional estimate in minutes, 1–1440 (0 is rejected)"),
        ]),
        "due_date": .object([
          "type": .string("string"),
          "description": .string("Optional YYYY-MM-DD external deadline."),
        ]),
        "planned_date": .object([
          "type": .string("string"),
          "description": .string("Optional YYYY-MM-DD planned work date."),
        ]),
        "available_from": .object([
          "type": .string("string"),
          "description": .string(
            "Optional YYYY-MM-DD not-before date. The task stays hidden from day surfaces (Today, Upcoming, widgets) until this date, unless it is overdue. Independent of planned_date and due_date. Not defer_task — this does not move the planned day or count as a deferral."),
        ]),
        "tags": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
          "description": .string("Initial task tags."),
        ]),
        "depends_on": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
          "description": .string("Initial dependency task ids."),
        ]),
        "checklist": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
          "description": .string(
            "Optional ordered initial checklist item texts. Each is appended as a checklist step in array order through the same validated path add_task_checklist_item uses (per-item change logged to ai_changelog). Capped at 200 items; each item must be non-empty and at most 1000 characters."),
        ]),
        "original_id": .object([
          "type": .string("string"),
          "description": .string(
            "Restore this task at a caller-supplied id instead of minting a new one. Use when re-creating an exported dataset so every reference to it — depends_on, task↔event links, review linked_ids, focus task_ids — resolves with no old→new id map. Omit for an ordinary new task."),
        ]),
        "status": .object([
          "type": .string("string"),
          "enum": .array([
            .string("open"), .string("in_progress"), .string("someday"),
            .string("completed"), .string("cancelled"),
          ]),
          "description": .string(
            "Initial status. Defaults to open. Pass completed/cancelled to re-create an already-resolved task, someday to park it, or in_progress to create it already started."),
        ]),
        "created_at": .object([
          "type": .string("string"),
          "description": .string(
            "Historical creation timestamp (ISO-8601) to preserve on re-create, so changelog chronology is not stamped 'now'. Omit for a new task."),
        ]),
        "completed_at": .object([
          "type": .string("string"),
          "description": .string(
            "Historical completion timestamp (ISO-8601) to preserve when re-creating an already-completed task. Omit unless restoring history."),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("title")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let updateTaskTool = Tool(
    name: "update_task",
    title: "Update Task",
    description: "Patch one task's editable fields (title, notes, raw_input, priority, due_date, planned_date, available_from, tags, depends_on, estimated_minutes). due_date (external deadline), planned_date (intended work day), and available_from (hide-until / not-before) are independent. Status transitions belong to complete_task, cancel_task, reopen_task, set_task_someday, and start_task/pause_task (the in_progress marker) — do not change status here. Only supplied fields are updated; an omitted field keeps its existing value; a supplied clearable field set to null/empty clears it. Returns the full updated task object.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "id": .object([
          "type": .string("string"),
          "description": .string("Task id"),
        ]),
        "title": .object([
          "type": .string("string"),
          "description": .string("Task title"),
        ]),
        "notes": .object([
          "type": .string("string"),
          "description": .string("Task notes"),
        ]),
        "raw_input": .object([
          "type": .string("string"),
          "description": .string(
            "The user's verbatim original capture text, preserved alongside the AI-parsed fields (backs transparent reasoning). Optional."
          ),
        ]),
        "priority": .object([
          "type": .string("integer"),
          "enum": .array([.int(1), .int(2), .int(3)]),
          "description": .string("Priority: 1 (highest), 2, or 3. A value outside 1–3 is rejected. Omit to keep the current priority."),
        ]),
        "estimated_minutes": .object([
          "type": .string("integer"),
          "description": .string("Optional estimate in minutes, 1–1440, or null to clear (0 is rejected)."),
        ]),
        "due_date": .object([
          "type": .string("string"),
          "description": .string(
            "Optional YYYY-MM-DD external deadline, or null/empty to clear. Independent of planned_date."),
        ]),
        "planned_date": .object([
          "type": .string("string"),
          "description": .string(
            "Optional YYYY-MM-DD planned work date, or null/empty to clear. Independent of due_date."),
        ]),
        "available_from": .object([
          "type": .string("string"),
          "description": .string(
            "Optional YYYY-MM-DD not-before date, or null/empty to clear. The task stays hidden from day surfaces until this date, unless it is overdue. Independent of planned_date and due_date. Not defer_task — this does not move the planned day or count as a deferral."),
        ]),
        "tags": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
          "description": .string("Replace the task tag set."),
        ]),
        "depends_on": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
          "description": .string("Replace the dependency task id set."),
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
