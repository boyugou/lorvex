import MCP

extension FocusToolCatalog {
  static let removeFromCurrentFocusTool = Tool(
    name: "remove_from_current_focus",
    title: "Remove From Current Focus",
    description: "Remove one task from the focus plan for a date without clearing the rest of the plan. Use when the user decides mid-day that a task shouldn't be in today's focus (e.g. it's now blocked, or a higher-priority item came up). The task itself is not changed — only its presence in the focus plan. Returns the updated focus plan.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "date": .object([
          "type": .string("string"),
          "description": .string(
            "YYYY-MM-DD focus date. Defaults to today in the configured product time zone when omitted, matching get_current_focus."),
        ]),
        "task_id": .object([
          "type": .string("string"),
          "description": .string("Task id to remove"),
        ]),
      ]),
      "required": .array([.string("task_id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let clearCurrentFocusTool = Tool(
    name: "clear_current_focus",
    title: "Clear Current Focus",
    description: "Remove all tasks from the focus plan for a date, leaving an empty plan. Use when the user wants to start planning from scratch. The briefing is also cleared. The tasks themselves are not changed. Prefer remove_from_current_focus when removing just one item mid-day. Returns the cleared (empty) focus plan.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "date": .object([
          "type": .string("string"),
          "description": .string(
            "YYYY-MM-DD focus date. Defaults to today in the configured product time zone when omitted, matching get_current_focus."),
        ])
      ]),
      "required": .array([]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )
}
