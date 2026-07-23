import MCP

extension ReviewToolCatalog {
  static let weeklyReviewBriefTool = Tool(
    name: "get_weekly_brief",
    title: "Get Weekly Brief",
    description: "Read a pre-populated weekly review brief. Use at the start of a weekly review session to orient the assistant before engaging the user. Each list section is bounded by its limit parameter. Returns {window {label, days}, completed_this_week, stalled_lists (lists with no recent completions), frequently_deferred, overdue_count, someday_items, created_this_week, estimate_summary, section_meta} where section_meta carries per-section limit/total_matching/returned/truncated counts.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "completed_limit": .object([
          "type": .string("integer"),
          "description": .string("Maximum completed tasks to return"),
        ]),
        "stalled_lists_limit": .object([
          "type": .string("integer"),
          "description": .string("Maximum stalled lists to return"),
        ]),
        "deferred_limit": .object([
          "type": .string("integer"),
          "description": .string("Maximum frequently deferred tasks to return"),
        ]),
        "someday_limit": .object([
          "type": .string("integer"),
          "description": .string("Maximum someday tasks to return"),
        ]),
      ]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let reviewHistoryTool = Tool(
    name: "get_review_history",
    title: "Get Review History",
    description: "Return daily review entries across a date window, newest first. Use to look at what the user wrote in past daily reviews, or to check whether a review was already created for a specific day. Returns paginated daily review objects with date, summary, wins, blockers, learnings, and linked task/list ids.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "from": .object([
          "type": .string("string"),
          "description": .string("Earliest date (YYYY-MM-DD, inclusive)."),
        ]),
        "to": .object([
          "type": .string("string"),
          "description": .string("Latest date (YYYY-MM-DD, inclusive)."),
        ]),
        "limit": .object([
          "type": .string("integer"),
          "description": .string("Maximum number of reviews to return. Defaults to 30."),
        ]),
      ]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

}
