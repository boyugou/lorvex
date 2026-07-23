import MCP

extension ListHabitToolCatalog {
  static let completeHabitTool = Tool(
    name: "complete_habit",
    title: "Complete Habit",
    description: "Record one completion for a habit on a date (defaults to today). For habits with target_count > 1, call multiple times to reach the target. Returns the full updated habit, including completions_today reflecting the new count.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "id": .object([
          "type": .string("string"),
          "description": .string("Habit id"),
        ]),
        "date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD completion date"),
        ]),
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

  static let batchCompleteHabitTool = Tool(
    name: "batch_complete_habits",
    title: "Batch Complete Habits",
    description: "Record one completion for each of the listed habits on the same date. Use at end of day or during a session check-in when the user has done multiple habits. Requires both habit_ids and date. Returns {results, count, date, skipped} where results is the full updated habit object for each completed id and skipped is [{id, reason}] for ids that were not found.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "habit_ids": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
          "description": .string("Habit ids to complete"),
        ]),
        "date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD completion date"),
        ]),
      ]),
      "required": .array([.string("habit_ids"), .string("date")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let adjustHabitCompletionTool = Tool(
    name: "adjust_habit_completion",
    title: "Adjust Habit Completion",
    description: "Increment or decrement the completion count for an accumulative habit (target_count > 1) on a date (defaults to today). Positive delta adds completions, negative removes them; the resulting count is clamped to [0, target_count]. For binary (target_count = 1) habits prefer complete_habit / uncomplete_habit. Returns the full updated habit, including completions_today reflecting the new count and reached_milestone (the milestone a positive adjust just crossed, or null).",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "id": .object([
          "type": .string("string"),
          "description": .string("Habit id"),
        ]),
        "date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD completion date"),
        ]),
        "delta": .object([
          "type": .string("integer"),
          "description": .string(
            "Completions to add (positive) or remove (negative); the new count is clamped to [0, target_count]"),
        ]),
      ]),
      "required": .array([.string("id"), .string("delta")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let uncompleteHabitTool = Tool(
    name: "uncomplete_habit",
    title: "Uncomplete Habit",
    description: "Remove all completion records for a habit on a specific date, resetting its count to 0 for that day. Use when the user says they didn't actually do the habit, or when a completion was logged by mistake. Returns the full updated habit.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "id": .object([
          "type": .string("string"),
          "description": .string("Habit id"),
        ]),
        "date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD completion date"),
        ]),
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
