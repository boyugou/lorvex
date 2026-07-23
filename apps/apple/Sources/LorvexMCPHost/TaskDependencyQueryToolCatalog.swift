import MCP

// MARK: - Dependency Graph + Upcoming Task Query Tool Definitions

extension TaskToolCatalog {
  static let dependencyGraphTool = Tool(
    name: "get_dependency_graph",
    title: "Get Dependency Graph",
    description:
      "Return the task dependency graph showing blocking relationships. By default only includes active tasks (open/someday). Use task_id to center on a specific task's neighbourhood, list_id to scope to a list. Returns nodes, edges, roots (no deps), blocked (unmet deps), and leaf_blockers (block others but are not themselves blocked — actionable first).",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "task_id": .object([
          "type": .string("string"),
          "description": .string("Center the graph on this task ID"),
        ]),
        "list_id": .object([
          "type": .string("string"),
          "description": .string("Scope nodes to this list"),
        ]),
        "include_inactive": .object([
          "type": .string("boolean"),
          "description": .string("Include completed/cancelled tasks. Default false."),
        ]),
      ]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let upcomingTasksTool = Tool(
    name: "get_upcoming_tasks",
    title: "Get Upcoming Tasks",
    description:
      "Return open tasks planned or due within the next N days. Returns a flat `tasks` array (the paginated page, same shape as list_tasks) plus a `by_date` grouping of those same rows for a week view. Use when the user asks about their week, when checking for deadline clusters, or during weekly review to identify upcoming load. Default task rows are compact; use shape=full, fields, or include to request heavier detail.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "days": .object([
          "type": .string("integer"),
          "description": .string("Number of days ahead to look. Default 7."),
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

  static let dueTaskRemindersTool = Tool(
    name: "get_due_task_reminders",
    title: "Get Due Task Reminders",
    description:
      "Return task reminders that are currently due (reminder_at <= now). Only includes reminders for open tasks that haven't been dismissed or cancelled. Returns {reminders} plus the shared pagination envelope; page with limit/offset following next_offset while truncated is true.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "as_of": .object([
          "type": .string("string"),
          "description": .string(
            "ISO 8601 timestamp cutoff. Defaults to now if omitted."),
        ]),
        "limit": .object([
          "type": .string("integer"),
          "description": .string("Maximum reminders to return, capped at 500. Default 50."),
        ]),
        "offset": .object([
          "type": .string("integer"),
          "description": .string("Zero-based pagination offset. Defaults to 0."),
        ]),
      ]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let upcomingTaskRemindersTool = Tool(
    name: "get_upcoming_task_reminders",
    title: "Get Upcoming Task Reminders",
    description:
      "Return task reminders due within the next N hours (default 24h, max 168h). Only includes reminders for open tasks that haven't been dismissed or cancelled. Returns {reminders} plus the shared pagination envelope; page with limit/offset following next_offset while truncated is true.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "hours": .object([
          "type": .string("integer"),
          "description": .string("Hours ahead to look. Default 24, max 168."),
        ]),
        "limit": .object([
          "type": .string("integer"),
          "description": .string("Maximum reminders to return, capped at 500. Default 50."),
        ]),
        "offset": .object([
          "type": .string("integer"),
          "description": .string("Zero-based pagination offset. Defaults to 0."),
        ]),
      ]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )
}
