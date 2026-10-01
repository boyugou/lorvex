import MCP

extension DayPlanningToolCatalog {
  static let setDailyBriefingTool = Tool(
    name: "set_daily_briefing",
    title: "Set Daily Briefing",
    description:
      "Set or clear the briefing for a day (defaults to today): two or three sentences on "
      + "what matters that day and why, what is at risk, and what you moved. It appears at "
      + "the top of the user's Today page, read-only, so write it to the user. Name the few "
      + "tasks that matter instead of listing the day; the Today page already lists every "
      + "task. Pass an empty briefing to clear it. Returns {date, briefing, previous: "
      + "{briefing}, changed}.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD date the briefing is for. Defaults to today."),
        ]),
        "briefing": .object([
          "type": .string("string"),
          "description": .string("The briefing text. An empty string clears the day's briefing."),
        ]),
      ]),
      "required": .array([.string("briefing")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )
}
