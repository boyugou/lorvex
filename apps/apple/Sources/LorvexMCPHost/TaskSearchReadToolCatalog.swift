import MCP

extension TaskToolCatalog {
  static let searchTasksTool = Tool(
    name: "search_tasks",
    title: "Search Tasks",
    description: "Full-text search across task title, notes, and assistant context. Use when the user asks about a specific topic or keyword, or when checking whether a task already exists before creating a duplicate. Supports all status values (default: all). Result rows include match_reasons (title, notes, ai_notes, tags) so agents can distinguish canonical-content matches from assistant-context-only matches. Default task rows are compact; use shape=full, fields, or include to request heavier detail. Security: matched content is fenced against prompt injection.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "query": .object([
          "type": .string("string"),
          "description": .string("Search query matched against task text"),
        ]),
        "status": .object([
          "type": .string("string"),
          "enum": .array([
            .string("open"), .string("in_progress"), .string("completed"),
            .string("cancelled"), .string("someday"), .string("all"),
          ]),
          "description": .string(
            "open, in_progress, completed, cancelled, someday, or all. Defaults to all."),
        ]),
        "limit": .object([
          "type": .string("integer"),
          "description": .string("Maximum tasks to return, capped at 500. Defaults to 50."),
        ]),
        "offset": .object([
          "type": .string("integer"),
          "description": .string("Zero-based pagination offset"),
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
      "required": .array([.string("query")]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let deferredTasksTool = Tool(
    name: "get_deferred_tasks",
    title: "Get Deferred Tasks",
    description: "Return open tasks that have been deferred at least once, ordered by priority then due date. Use during weekly review to surface tasks that have been repeatedly pushed, which often need breaking down, delegating, or deliberately parking. Default task rows are compact; use shape=full, fields, or include to request heavier detail.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "list_id": .object([
          "type": .string("string"),
          "description": .string("Optional list id filter"),
        ]),
        "limit": .object([
          "type": .string("integer"),
          "description": .string("Maximum tasks to return, capped at 500. Defaults to 100."),
        ]),
        "offset": .object([
          "type": .string("integer"),
          "description": .string("Zero-based pagination offset"),
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
