import MCP

extension TaskToolCatalog {
  static let getTaskTool = Tool(
    name: "get_task",
    title: "Get Task",
    description:
      "Read one Lorvex task with enriched detail such as tags, dependencies, checklist items, reminders, lateness state, and a read-only defer_history (recent defer events with their structured reason and any free-text note, newest first).",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "id": .object([
          "type": .string("string"),
          "description": .string("Task id"),
        ])
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let listTasksTool = Tool(
    name: "list_tasks",
    title: "List Tasks",
    description:
      "Read a bounded page of Lorvex tasks. This is the primary task-context tool for planning and review: filter by status, list, priority, tags, text, lifecycle dates, due/planned/scheduled dates, and dependency state. "
      + "Default task rows are compact and omit null/empty heavy fields to save agent context. Use shape=full for complete rows, fields for exact fields, or include for field groups such as notes, ai_notes, dependencies, checklist, reminders, recurrence, defer, and lateness.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "status": .object([
          "type": .string("string"),
          "enum": .array([
            .string("open"), .string("in_progress"), .string("actionable"),
            .string("completed"), .string("cancelled"), .string("someday"),
            .string("all"),
          ]),
          "description": .string(
            "Filter by task status. Defaults to actionable (open + in_progress) so started work surfaces alongside open work — start_task/pause_task toggle the in_progress marker. open returns only not-yet-started tasks; in_progress returns only started ones. Use all to return every status."
          ),
        ]),
        "list_id": .object([
          "type": .string("string"),
          "description": .string("Optional list id filter"),
        ]),
        "priority": .object([
          "type": .string("integer"),
          "enum": .array([.int(1), .int(2), .int(3)]),
          "description": .string("Optional priority filter: 1 (highest), 2 (normal), 3 (low)."),
        ]),
        "text": .object([
          "type": .string("string"),
          "description": .string(
            "Case-insensitive substring match over task title, body, and AI notes."
          ),
        ]),
        "tags": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
          "description": .string("Optional tag names. All listed tags must match."),
        ]),
        "due_from": .object([
          "type": .string("string"),
          "description": .string("Earliest due_date (YYYY-MM-DD), inclusive."),
        ]),
        "due_to": .object([
          "type": .string("string"),
          "description": .string("Latest due_date (YYYY-MM-DD), inclusive."),
        ]),
        "planned_from": .object([
          "type": .string("string"),
          "description": .string("Earliest planned_date (YYYY-MM-DD), inclusive."),
        ]),
        "planned_to": .object([
          "type": .string("string"),
          "description": .string("Latest planned_date (YYYY-MM-DD), inclusive."),
        ]),
        "available_from_from": .object([
          "type": .string("string"),
          "description": .string("Earliest available_from / not-before date (YYYY-MM-DD), inclusive."),
        ]),
        "available_from_to": .object([
          "type": .string("string"),
          "description": .string("Latest available_from / not-before date (YYYY-MM-DD), inclusive."),
        ]),
        "availability": .object([
          "type": .string("string"),
          "enum": .array([.string("visible"), .string("hidden"), .string("all")]),
          "description": .string(
            "Not-before (available_from) visibility for the open/actionable lanes: 'visible' hides tasks whose available_from is a future date (unless overdue), 'hidden' returns only those hidden not-yet-available tasks, 'all' applies no filter. Applies only to the open and actionable (open + in_progress) lanes; ignored for other status lanes. Defaults to 'all'."),
        ]),
        "scheduled_from": .object([
          "type": .string("string"),
          "description": .string(
            "Earliest scheduled day (COALESCE(planned_date, due_date), YYYY-MM-DD), inclusive."),
        ]),
        "scheduled_to": .object([
          "type": .string("string"),
          "description": .string(
            "Latest scheduled day (COALESCE(planned_date, due_date), YYYY-MM-DD), inclusive."),
        ]),
        "completed_from": .object([
          "type": .string("string"),
          "description": .string("Earliest completed_at timestamp or YYYY-MM-DD, inclusive."),
        ]),
        "completed_to": .object([
          "type": .string("string"),
          "description": .string("Latest completed_at timestamp or YYYY-MM-DD, inclusive."),
        ]),
        "created_from": .object([
          "type": .string("string"),
          "description": .string("Earliest created_at timestamp or YYYY-MM-DD, inclusive."),
        ]),
        "created_to": .object([
          "type": .string("string"),
          "description": .string("Latest created_at timestamp or YYYY-MM-DD, inclusive."),
        ]),
        "updated_from": .object([
          "type": .string("string"),
          "description": .string("Earliest updated_at timestamp or YYYY-MM-DD, inclusive."),
        ]),
        "updated_to": .object([
          "type": .string("string"),
          "description": .string("Latest updated_at timestamp or YYYY-MM-DD, inclusive."),
        ]),
        "due_presence": .object([
          "type": .string("string"),
          "enum": .array([.string("any"), .string("present"), .string("absent")]),
          "description": .string("Filter tasks by whether due_date is present or absent."),
        ]),
        "planned_presence": .object([
          "type": .string("string"),
          "enum": .array([.string("any"), .string("present"), .string("absent")]),
          "description": .string("Filter tasks by whether planned_date is present or absent."),
        ]),
        "blocked_only": .object([
          "type": .string("boolean"),
          "description": .string("Only return tasks blocked by an active dependency."),
        ]),
        "blocking_others": .object([
          "type": .string("boolean"),
          "description": .string("Only return tasks that block at least one active dependent task."),
        ]),
        "sort_by": .object([
          "type": .string("string"),
          "enum": .array([
            .string("priority_due"), .string("due_date"), .string("planned_date"),
            .string("updated_at"), .string("created_at"), .string("title"),
          ]),
          "description": .string("Sort axis. Defaults to priority_due."),
        ]),
        "sort_direction": .object([
          "type": .string("string"),
          "enum": .array([.string("asc"), .string("desc")]),
          "description": .string("Sort direction for the leading axis. Defaults to asc."),
        ]),
        "limit": .object([
          "type": .string("integer"),
          "description": .string("Maximum tasks to return, capped at 500. Defaults to 100."),
        ]),
        "offset": .object([
          "type": .string("integer"),
          "description": .string("Zero-based pagination offset. Defaults to 0."),
        ]),
        "shape": .object([
          "type": .string("string"),
          "enum": .array([.string("compact"), .string("full")]),
          "description": .string(
            "Task row shape. compact is the default and omits null/empty heavy fields; full preserves the complete task row."),
        ]),
        "include_nulls": .object([
          "type": .string("boolean"),
          "description": .string(
            "Include explicit null values in task rows. Defaults to false for compact and true for full."),
        ]),
        "fields": .object([
          "type": .string("array"),
          "items": .object([
            "type": .string("string"),
            "enum": .array(TaskValueOptions.fieldNames.map(Value.string)),
          ]),
          "description": .string(
            "Exact task fields to return. id is always included. Overrides the compact/full field set."),
        ]),
        "include": .object([
          "type": .string("array"),
          "items": .object([
            "type": .string("string"),
            "enum": .array(TaskValueOptions.includeValues.map(Value.string)),
          ]),
          "description": .string(
            "Additional field groups or field names to include with compact rows: notes, ai_notes, scheduling, lifecycle, tags, dependencies, checklist, reminders, recurrence, defer, lateness."),
        ]),
      ]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )
}
