import MCP

enum BatchTaskToolCatalog {
  static let batchCreateTool =
    Tool(
      name: "batch_create_tasks",
      title: "Batch Create Tasks",
      description:
        "Create multiple Lorvex tasks in one call for brain dumps, imports, and related task batches. Each task also accepts original_id (id-preserving re-create), status, historical created_at/completed_at, and an ordered checklist, like create_task. Validates and creates each row independently: a bad row is reported and the rest still land. Returns {results, count, skipped} where results is the new task objects (including any checklist items), count is their number, and skipped is per-item failures as [{id, reason}].",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "tasks": .object([
            "type": .string("array"),
            "maxItems": .int(MCPBatchLimits.maxItems),
            "items": .object([
              "type": .string("object"),
              "properties": .object([
                "title": .object(["type": .string("string")]),
                "notes": .object(["type": .string("string")]),
                "priority": .object([
                  "type": .string("integer"),
                  "enum": .array([.int(1), .int(2), .int(3)]),
                  "description": .string("Priority: 1 (highest), 2, or 3."),
                ]),
                "estimated_minutes": .object([
                  "type": .string("integer"),
                  "description": .string("Optional estimate in minutes, 1–1440 (0 is rejected)."),
                ]),
                "due_date": .object([
                  "type": .string("string"),
                  "description": .string(
                    "Optional YYYY-MM-DD external deadline. Independent of planned_date."),
                ]),
                "planned_date": .object([
                  "type": .string("string"),
                  "description": .string(
                    "Optional YYYY-MM-DD planned work date. Independent of due_date."),
                ]),
                "available_from": .object([
                  "type": .string("string"),
                  "description": .string(
                    "Optional YYYY-MM-DD not-before date. Hidden from day surfaces until then, unless overdue. Not defer_task — this does not move the planned day or count as a deferral."),
                ]),
                "list_id": .object(["type": .string("string")]),
                "tags": .object([
                  "type": .string("array"),
                  "items": .object(["type": .string("string")]),
                  "description": .string("Initial task tags."),
                ]),
                "depends_on": .object([
                  "type": .string("array"),
                  "items": .object(["type": .string("string")]),
                ]),
                "checklist": .object([
                  "type": .string("array"),
                  "items": .object(["type": .string("string")]),
                  "description": .string(
                    "Optional ordered initial checklist item texts, each appended as a checklist step in array order through the same validated path add_task_checklist_item uses. Capped at 200 items; each item must be non-empty and at most 1000 characters."),
                ]),
                "original_id": .object([
                  "type": .string("string"),
                  "description": .string(
                    "Restore this task at a caller-supplied id (id-preserving re-create) instead of minting a new one. Omit for an ordinary new task."),
                ]),
                "status": .object([
                  "type": .string("string"),
                  "enum": .array([
                    .string("open"), .string("in_progress"), .string("someday"),
                    .string("completed"), .string("cancelled"),
                  ]),
                  "description": .string(
                    "Initial status. Defaults to open."),
                ]),
                "created_at": .object([
                  "type": .string("string"),
                  "description": .string(
                    "Historical creation timestamp (ISO-8601) to preserve on re-create."),
                ]),
                "completed_at": .object([
                  "type": .string("string"),
                  "description": .string(
                    "Historical completion timestamp (ISO-8601) to preserve when re-creating a completed task."),
                ]),
              ]),
              "required": .array([.string("title")]),
            ]),
          ]),
          "include_advice": .object([
            "type": .string("boolean"),
            "description": .string("Include bounded deterministic intake advice per task"),
          ]),
          IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        ]),
        "required": .array([.string("tasks")]),
      ]),
      annotations: .init(
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false
      )
    )

  static let batchUpdateTool =
    Tool(
      name: "batch_update_tasks",
      title: "Batch Update Tasks",
      description:
        "Patch multiple tasks in one bounded call. Each update entry specifies task id and only the fields to change; omitted fields are left unchanged. Supports title, notes, priority, due_date, planned_date, available_from, tags, depends_on, and estimated_minutes per task. due_date (external deadline), planned_date (intended work day), and available_from (hide-until / not-before) are independent. To move tasks between lists use move_task_to_list; to change status use complete/cancel/reopen/defer or start/pause (the in_progress marker), or their batch variants. Returns {results, count, skipped} where results is the patched task objects, count is their number, and skipped is per-item failures ([{id, reason}], empty today).",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "updates": .object([
            "type": .string("array"),
            "maxItems": .int(MCPBatchLimits.maxItems),
            "items": .object([
              "type": .string("object"),
              "properties": .object([
                "id": .object(["type": .string("string")]),
                "title": .object(["type": .string("string")]),
                "notes": .object(["type": .string("string")]),
                "priority": .object([
                  "type": .string("integer"),
                  "enum": .array([.int(1), .int(2), .int(3)]),
                  "description": .string("Priority: 1 (highest), 2, or 3."),
                ]),
                "estimated_minutes": .object([
                  "type": .string("integer"),
                  "description": .string("Estimate in minutes, 1–1440, or null to clear (0 is rejected)."),
                ]),
                "due_date": .object([
                  "type": .string("string"),
                  "description": .string(
                    "YYYY-MM-DD external deadline. Independent of planned_date."),
                ]),
                "planned_date": .object([
                  "type": .string("string"),
                  "description": .string(
                    "YYYY-MM-DD planned work date. Independent of due_date."),
                ]),
                "available_from": .object([
                  "type": .string("string"),
                  "description": .string(
                    "YYYY-MM-DD not-before date, or null to clear. Hidden from day surfaces until then, unless overdue. Not defer_task — this does not move the planned day or count as a deferral."),
                ]),
                "tags": .object([
                  "type": .string("array"),
                  "items": .object(["type": .string("string")]),
                  "description": .string("Replace the task tag set."),
                ]),
                "depends_on": .object([
                  "type": .string("array"),
                  "items": .object(["type": .string("string")]),
                ]),
              ]),
              "required": .array([.string("id")]),
            ]),
          ]),
          IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        ]),
        "required": .array([.string("updates")]),
      ]),
      annotations: .init(
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false
      )
    )
}
