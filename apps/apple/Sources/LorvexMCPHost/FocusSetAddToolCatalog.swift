import MCP

extension FocusToolCatalog {
  static let setCurrentFocusTool = Tool(
    name: "set_current_focus",
    title: "Set Current Focus",
    description: "Replace the current focus plan for a date with a new task list. Use this when planning from scratch or discarding the current plan entirely. To add tasks without clearing existing entries, use add_to_current_focus instead. The optional briefing field accepts free-text Markdown with context (priorities, blockers, energy level) that the AI can use when reasoning about the schedule. Example: set date=2026-05-26, task_ids=[task-abc], briefing=Focus on the demo build. Returns the updated focus plan.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "date": .object([
          "type": .string("string"),
          "description": .string(
            "YYYY-MM-DD focus date. Defaults to today in the configured product time zone when omitted, matching get_current_focus."),
        ]),
        "task_ids": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
        ]),
        "briefing": .object([
          "type": .string("string"),
          "description": .string("Optional focus briefing"),
        ]),
        "timezone": .object([
          "type": .string("string"),
          "description": .string(
            "Optional IANA timezone. Defaults to the user's configured timezone when omitted."),
        ]),
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

  static let addToCurrentFocusTool = Tool(
    name: "add_to_current_focus",
    title: "Add To Current Focus",
    description: "Append tasks to the current focus plan for a date without clearing existing entries. Use this when the user wants to add one or a few tasks to an already-planned day. To replace the plan entirely, use set_current_focus instead. The optional briefing field accepts free-text Markdown with context (priorities, blockers, energy level) that the AI can use when reasoning about additions. Example: add date=2026-05-26, task_ids=[task-xyz], briefing=Just found a P1 bug, slot it in. Returns the updated focus plan.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "date": .object([
          "type": .string("string"),
          "description": .string(
            "YYYY-MM-DD focus date. Defaults to today in the configured product time zone when omitted, matching get_current_focus."),
        ]),
        "task_ids": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
        ]),
        "briefing": .object([
          "type": .string("string"),
          "description": .string("Optional focus briefing"),
        ]),
        "timezone": .object([
          "type": .string("string"),
          "description": .string(
            "Optional IANA timezone. Defaults to the user's configured timezone when omitted."),
        ]),
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
}
