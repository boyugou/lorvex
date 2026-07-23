import MCP

extension FocusToolCatalog {
  static let getCurrentFocusTool = Tool(
    name: "get_current_focus",
    title: "Get Current Focus",
    description: "Return the compact focus plan for a date (defaults to today): date, task_ids, task_count, and briefing/timezone when saved. Use when the user asks what to focus on, before proposing plan changes, or to check if a plan already exists. Returns an empty plan shape when no plan exists.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD focus date"),
        ])
      ]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let getSavedFocusScheduleTool = Tool(
    name: "get_saved_focus_schedule",
    title: "Get Saved Focus Schedule",
    description: "Read the saved time-blocked focus schedule for a date (defaults to today). Returns time-block assignments, or null if no schedule was saved. Check this before proposing a new schedule to avoid overwriting an existing one. The schedule is separate from the current focus plan: the plan is the priority list, the schedule is the time-blocked calendar of when to work on each item.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD focus date"),
        ])
      ]),
    ]),
    annotations: .init(
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )
}
