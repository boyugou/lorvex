import MCP

enum ReviewToolCatalog {
  static let dailyReviewTool = Tool(
    name: "get_daily_review",
    title: "Get Daily Review",
    description: "Read a daily review entry for a date (defaults to today). Returns the summary, mood/energy ratings, wins, blockers, learnings, and linked task/list ids. Returns null if no review exists for that date — use add_daily_review to create one.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "date": .object([
          "type": .string("string"),
          "description": .string(
            "YYYY-MM-DD date. Defaults to the current date in Lorvex's configured timezone."),
        ])
      ]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let amendDailyReviewTool = Tool(
    name: "amend_daily_review",
    title: "Amend Daily Review",
    description: "Patch individual fields of an existing Lorvex daily review. Only provided fields are updated; omitted fields are left unchanged. Returns the updated review.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD date of the review to amend."),
        ]),
        "summary": .object(["type": .string("string")]),
        "mood": .object(["type": .string("integer"), "description": .string("Mood 1-5")]),
        "energy_level": .object([
          "type": .string("integer"), "description": .string("Energy 1-5"),
        ]),
        "wins": .object(["type": .string("string")]),
        "blockers": .object(["type": .string("string")]),
        "learnings": .object(["type": .string("string")]),
        "linked_task_ids": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
        ]),
        "linked_list_ids": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
        ]),
      ]),
      "required": .array([.string("date")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let addDailyReviewTool = Tool(
    name: "add_daily_review",
    title: "Add Daily Review",
    description: "Create or fully replace the daily review for a date (defaults to today). All fields are optional except summary. Use at the end of a day or session to record progress, mood, wins, blockers, and learnings. Prefer amend_daily_review when updating one field of an existing review without overwriting others, or to link specific tasks/lists to the review. Returns the saved review.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "date": .object([
          "type": .string("string"),
          "description": .string(
            "YYYY-MM-DD date. Defaults to the current date in Lorvex's configured timezone."),
        ]),
        "summary": .object([
          "type": .string("string"),
          "description": .string("2-4 sentence prose summary of the day"),
        ]),
        "mood": .object([
          "type": .string("integer"),
          "description": .string("Mood 1-5"),
        ]),
        "energy_level": .object([
          "type": .string("integer"),
          "description": .string("Energy 1-5"),
        ]),
        "wins": .object(["type": .string("string")]),
        "blockers": .object(["type": .string("string")]),
        "learnings": .object(["type": .string("string")]),
        "linked_task_ids": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
          "description": .string("Task ids linked to this replacement review. Omit or pass [] to clear existing task links."),
        ]),
        "linked_list_ids": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
          "description": .string("List ids linked to this replacement review. Omit or pass [] to clear existing list links."),
        ]),
      ]),
      "required": .array([.string("summary")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )
}
