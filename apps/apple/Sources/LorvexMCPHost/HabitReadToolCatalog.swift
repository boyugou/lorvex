import MCP

extension ListHabitToolCatalog {
  static let getHabitsTool = Tool(
    name: "get_habits",
    title: "Get Habits",
    description: "Return all active habits with today's completion count and progress toward target_count. Use at the start of a session to see which habits are done, in progress, or not yet started. Optionally pass a date to check completion state for a different day. Returns {habits} where each habit includes completions_today, target_count, and total_completions. For one habit's streak/rate detail, call get_habit_stats; for the same enrichment across every habit in one review sweep, pass include_stats: true (each row then also carries current_streak, best_streak, completion_rate_30d, and progress_kind).",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "date": .object([
          "type": .string("string"),
          "description": .string(
            "YYYY-MM-DD date. Defaults to the current date in Lorvex's configured timezone."),
        ]),
        "include_stats": .object([
          "type": .string("boolean"),
          "description": .string(
            "When true, enrich each habit row with the streak/rate fields get_habit_stats computes (current_streak, best_streak, completion_rate_30d, progress_kind), via the per-habit stats query. Defaults to false."),
        ]),
      ]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let getHabitCompletionsTool = Tool(
    name: "get_habit_completions",
    title: "Get Habit Completions",
    description:
      "List recent completion records for a habit, newest first. Bounded by limit (default 100, max 500); the response carries the shared pagination envelope (returned, limit, truncated). When truncated is true, narrow the from/to window to see older records.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "habit_id": .object(["type": .string("string"), "description": .string("Habit id")]),
        "from": .object(["type": .string("string"), "description": .string("YYYY-MM-DD lower bound")]),
        "to": .object(["type": .string("string"), "description": .string("YYYY-MM-DD upper bound")]),
        "limit": .object([
          "type": .string("integer"),
          "description": .string(
            "Max records to return, newest first. Defaults to 100, capped at 500."),
        ]),
      ]),
      "required": .array([.string("habit_id")]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let getHabitStatsTool = Tool(
    name: "get_habit_stats",
    title: "Get Habit Stats",
    description: "Return streak and performance statistics for one habit: name, current streak, best streak ever, total completion value, today's completion value, 30-day completion rate, and milestone standing (milestone_metric, milestone_value, milestone_target, next_milestone, progress_to_next). For accumulative habits, total_completions is the SUM of recorded values, not the number of days with a row. Use get_habit_completions when you need per-day records. For the same streak/rate fields across every habit at once, use get_habits(include_stats: true).",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "habit_id": .object(["type": .string("string"), "description": .string("Habit id")]),
      ]),
      "required": .array([.string("habit_id")]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )
}
