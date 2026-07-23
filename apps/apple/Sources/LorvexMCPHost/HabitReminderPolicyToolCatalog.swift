import MCP

extension ListHabitToolCatalog {
  static let getHabitReminderPoliciesTool = Tool(
    name: "get_habit_reminder_policies",
    title: "Get Habit Reminder Policies",
    description: "List reminder policies for one habit, or all habits when habit_id is omitted.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "habit_id": .object([
          "type": .string("string"),
          "description": .string("Optional habit id filter"),
        ])
      ]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let upsertHabitReminderPolicyTool = Tool(
    name: "upsert_habit_reminder_policy",
    title: "Upsert Habit Reminder Policy",
    description: "Set a daily reminder time for a habit. Supply habit_id and reminder_time (HH:MM 24-hour). Use when the user asks to be reminded about a habit at a specific time each day. Omit id to create a new policy; supply id to update an existing one. Returns the upserted reminder policy.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "id": .object([
          "type": .string("string"),
          "description": .string("Optional existing policy id"),
        ]),
        "habit_id": .object([
          "type": .string("string"),
          "description": .string("Habit id"),
        ]),
        "reminder_time": .object([
          "type": .string("string"),
          "description": .string("HH:MM reminder time"),
        ]),
        "enabled": .object([
          "type": .string("boolean"),
          "description": .string("Whether the reminder is enabled. Defaults to true."),
        ]),
      ]),
      "required": .array([.string("habit_id"), .string("reminder_time")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )

  static let deleteHabitReminderPolicyTool = Tool(
    name: "delete_habit_reminder_policy",
    title: "Delete Habit Reminder Policy",
    description: "Delete a habit reminder policy by id. Use when the user no longer wants reminders for a habit, or when replacing an existing policy. Returns {deleted, id, previous} where previous is the removed policy.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "id": .object([
          "type": .string("string"),
          "description": .string("Policy id to delete"),
        ]),
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
}
