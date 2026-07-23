import MCP

extension ListHabitToolCatalog {
  static let createHabitTool = Tool(
    name: "create_habit",
    title: "Create Habit",
    description: "Create a trackable habit. Supply name (required), an optional cue prompt (e.g. 'After morning coffee, …'), an optional target_count (the per-DAY accumulative goal; defaults to 1, set >1 for habits like 'drink 8 glasses of water'), an optional cadence (which periods are scheduled; defaults to daily), an optional milestone_target (a personal goal to celebrate reaching), and optional appearance: icon (an SF Symbol name such as 'drop', 'book', 'dumbbell', 'moon') and color (a #RRGGBB hex such as '#3B82F6'). The cadence is set with frequency_type plus one detail field: weekly uses weekdays, times_per_week uses per_period_target, monthly uses day_of_month. target_count is the per-day goal and is fully independent of the cadence: a '3 times per week' habit is frequency_type=times_per_week with per_period_target=3, NOT target_count=3. Returns the created habit.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "original_id": .object([
          "type": .string("string"),
          "description": .string(
            "Restore this habit at a caller-supplied id instead of minting a new one, so its exported completion history (keyed by habit id) re-attaches on re-create. Omit for an ordinary new habit."),
        ]),
        "name": .object([
          "type": .string("string"),
          "description": .string("Habit name"),
        ]),
        "cue": .object([
          "type": .string("string"),
          "description": .string("Optional cue text"),
        ]),
        "target_count": .object([
          "type": .string("integer"),
          "description": .string("Per-day accumulative goal: the number of check-ins that complete one scheduled day (e.g. 8 for 'drink 8 glasses of water'). Fully independent of the cadence. Defaults to 1."),
        ]),
        "frequency_type": .object([
          "type": .string("string"),
          "enum": .array([
            .string("daily"), .string("weekly"), .string("monthly"), .string("times_per_week"),
          ]),
          "description": .string("Cadence rhythm: daily, weekly, monthly, or times_per_week. Defaults to daily."),
        ]),
        "weekdays": .object([
          "type": .string("array"),
          "items": .object(["type": .string("integer")]),
          "description": .string("For frequency_type=weekly: the scheduled weekdays as integers, Monday-first (0=Mon, 1=Tue, … 6=Sun). Omit or empty means every day. Ignored for other cadences."),
        ]),
        "per_period_target": .object([
          "type": .string("integer"),
          "description": .string("For frequency_type=times_per_week: how many completions per week (e.g. 3 for '3×/week'). Ignored for other cadences."),
        ]),
        "day_of_month": .object([
          "type": .string("integer"),
          "description": .string("For frequency_type=monthly: the day (1–31) the reminder fires, clamped to the month's last day. Ignored for other cadences."),
        ]),
        "milestone_target": .object([
          "type": .string("integer"),
          "description": .string("Optional milestone goal — a positive count in the habit's metric (streak length for daily/weekly, total completions for monthly/times_per_week). Reaching it is flagged on complete_habit. Omit for none."),
        ]),
        "icon": .object([
          "type": .string("string"),
          "description": .string("Optional SF Symbol name (e.g. 'drop', 'book', 'moon'). Omit for the default glyph."),
        ]),
        "color": .object([
          "type": .string("string"),
          "description": .string("Optional #RRGGBB hex accent (e.g. '#3B82F6'). Omit for the auto color."),
        ]),
      ]),
      "required": .array([.string("name")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let updateHabitTool = Tool(
    name: "update_habit",
    title: "Update Habit",
    description: "Update a habit's name, cue prompt, color, icon, target count, cadence, milestone_target, or archived state. Only supplied fields are changed; a supplied frequency_type replaces the WHOLE cadence (send its detail field too: weekdays for weekly, per_period_target for times_per_week, day_of_month for monthly). Pass milestone_target as a positive integer to set the goal or null to clear it; omit it to leave it unchanged. Set archived=true to archive a habit (hidden from the active list, history preserved) or archived=false to restore it — prefer this over delete_habit, which is irreversible. Returns the updated habit.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "id": .object(["type": .string("string"), "description": .string("Habit id")]),
        "name": .object(["type": .string("string")]),
        "cue": .object(["type": .string("string")]),
        "color": .object([
          "type": .string("string"),
          "description": .string("#RRGGBB hex accent (e.g. '#3B82F6')"),
        ]),
        "icon": .object([
          "type": .string("string"),
          "description": .string("SF Symbol name (e.g. 'drop', 'book', 'moon')"),
        ]),
        "target_count": .object([
          "type": .string("integer"),
          "description": .string("Per-day accumulative goal (independent of the cadence)."),
        ]),
        "frequency_type": .object([
          "type": .string("string"),
          "enum": .array([
            .string("daily"), .string("weekly"), .string("monthly"), .string("times_per_week"),
          ]),
          "description": .string("Replace the cadence rhythm: daily, weekly, monthly, or times_per_week. Omit to leave unchanged."),
        ]),
        "weekdays": .object([
          "type": .string("array"),
          "items": .object(["type": .string("integer")]),
          "description": .string("For frequency_type=weekly: scheduled weekdays as integers, Monday-first (0=Mon … 6=Sun). Omit or empty means every day."),
        ]),
        "per_period_target": .object([
          "type": .string("integer"),
          "description": .string("For frequency_type=times_per_week: completions per week (e.g. 3 for '3×/week')."),
        ]),
        "day_of_month": .object([
          "type": .string("integer"),
          "description": .string("For frequency_type=monthly: the reminder day (1–31)."),
        ]),
        "milestone_target": .object([
          "type": .string("integer"),
          "description": .string("Positive milestone goal to set, or null to clear it. Omit to leave the current goal unchanged."),
        ]),
        "archived": .object([
          "type": .string("boolean"),
          "description": .string("true archives (hides) the habit; false restores it."),
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

  static let deleteHabitTool = Tool(
    name: "delete_habit",
    title: "Delete Habit",
    description: "Permanently delete a habit and all its completion history. This is irreversible. Use when the user abandons a habit entirely, as opposed to archiving it. Returns {deleted, id, previous} where previous is the removed habit object.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "id": .object(["type": .string("string"), "description": .string("Habit id")]),
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: false
    )
  )

  static let reorderHabitsTool = Tool(
    name: "reorder_habits",
    title: "Reorder Habits",
    description: "Set the manual display order of the active habits board. Supply the active habit ids in the desired order; each listed habit's position is rewritten to its index, so the order converges across devices as an ordinary synced field. Ids omitted from the array keep their current position and ids that no longer resolve are skipped. This never creates, deletes, or archives a habit — use create_habit / delete_habit / update_habit for that. Optionally pass a date to project the returned completion counts for a different day. Returns the full refreshed habits board in the new order.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "habit_ids": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
          "description": .string("Active habit ids in the desired display order"),
        ]),
        "date": .object([
          "type": .string("string"),
          "description": .string(
            "YYYY-MM-DD date for the returned completion counts. Defaults to the current date in Lorvex's configured timezone."),
        ]),
      ]),
      "required": .array([.string("habit_ids")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )
}
