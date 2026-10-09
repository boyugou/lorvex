import MCP

extension ListHabitToolCatalog {
  static let skipHabitTool = Tool(
    name: "skip_habit",
    title: "Skip Habit",
    description: "Set a habit aside for one day (defaults to today) as an excused day. The day is neither done nor missed: a daily or weekly habit's streak carries across it, the day leaves that habit's completion rate, and the daily review stops counting the habit as open. A monthly or times-per-week habit only marks the day as set aside. Use when the user chooses to skip a habit on purpose (tired, ill, travelling); when they simply did not do it, record nothing. Refused when the habit already has a check-in on that date (call uncomplete_habit first) or is archived. Skipping a day that is already skipped changes nothing, and checking the habit in on a skipped day removes the skip. Returns the full updated habit, including skipped_today.",
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
          "description": .string("YYYY-MM-DD day to skip. Defaults to today."),
        ]),
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )

  static let unskipHabitTool = Tool(
    name: "unskip_habit",
    title: "Unskip Habit",
    description: "Take back a skip so the day counts as open again (date defaults to today). Use when the user changes their mind or a skip was recorded by mistake. Taking back a day that was not skipped changes nothing. Returns the full updated habit, including skipped_today.",
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
          "description": .string("YYYY-MM-DD day whose skip to take back. Defaults to today."),
        ]),
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )
}
