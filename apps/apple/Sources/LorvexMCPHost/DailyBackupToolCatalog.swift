import MCP

/// Tool descriptors for the daily backups the Mac app keeps of its own data.
enum DailyBackupToolCatalog {
  static let listDailyBackupsTool = Tool(
    name: "list_daily_backups",
    title: "List Daily Backups",
    description:
      "Lists the daily backups this Mac keeps of the user's Lorvex data, newest first: the day "
      + "each was taken, when it was written, and its size. Lorvex saves one full copy a day "
      + "and keeps the last 7 days plus one copy from each of the 4 weeks before, on this Mac "
      + "only. `enabled` is false when "
      + "the user turned daily backups off in Settings; only the user can turn them on or off. "
      + "Use compare_with_daily_backup to see what changed since a backup.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([:]),
    ]),
    annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
  )

  private static let categoryEnum: [Value] = DailyBackupComparison.categories.map { .string($0) }

  static let compareWithDailyBackupTool = Tool(
    name: "compare_with_daily_backup",
    title: "Compare with Daily Backup",
    description:
      "Compares the user's current Lorvex data with the daily backup from `day` and returns, per "
      + "category, what the backup has that is gone now (`removed`, in full), what is new since "
      + "(`added`, by id and title), and what differs (`changed`: partial `backup` and `now` "
      + "records with only the differing fields). Use it when the user wants back something "
      + "deleted or overwritten. To bring a removed item back, create it again from its "
      + "`removed` record with the usual tools; it gets a new id, because a deleted item's id "
      + "is never reused. To restore a changed field, update the item. Prefer undo_ai_change "
      + "for a recent assistant change. Get the days from list_daily_backups. Preferences are "
      + "not compared.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "day": .object([
          "type": .string("string"),
          "description": .string("The backup's day, YYYY-MM-DD, as list_daily_backups gives it."),
        ]),
        "entities": .object([
          "type": .string("array"),
          "items": .object([
            "type": .string("string"),
            "enum": .array(categoryEnum),
          ]),
          "description": .string("Categories to compare. Defaults to all of them."),
        ]),
        "ids": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
          "description": .string(
            "Only compare the records with these ids (a review's or briefing's date, a memory "
            + "entry's key, either id of a task-event link)."),
        ]),
        "limit": .object([
          "type": .string("integer"),
          "minimum": .int(1),
          "maximum": .int(DailyBackupToolLimits.maximum),
          "description": .string(
            "Most entries per list (removed, added, changed) per category. Defaults to "
            + "\(DailyBackupToolLimits.defaultLimit). Counts are always complete."),
        ]),
      ]),
      "required": .array([.string("day")]),
    ]),
    annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
  )
}

enum DailyBackupToolLimits {
  static let defaultLimit = 50
  static let maximum = 200
}
