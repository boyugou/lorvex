import MCP

enum TaskReminderToolCatalog {
  static let addReminderTool = Tool(
    name: "add_task_reminder",
    title: "Add Task Reminder",
    description: "Add a reminder notification to a task at a specific time. Supply reminder_at as a full RFC 3339 UTC timestamp (e.g. 2026-05-23T17:00:00Z). The system will schedule a local notification at that time. A task can have multiple reminders. Returns the full updated task with all reminders.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "task_id": .object(["type": .string("string")]),
        "reminder_at": .object([
          "type": .string("string"),
          "description": .string("RFC 3339 datetime, for example 2026-05-23T17:00:00Z"),
        ]),
      ]),
      "required": .array([.string("task_id"), .string("reminder_at")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let removeReminderTool = Tool(
    name: "remove_task_reminder",
    title: "Remove Task Reminder",
    description: "Remove a specific reminder from a task. Requires both task_id and the reminder's own id (from the reminders array in get_task or list_tasks). Also cancels the scheduled notification. Returns the full updated task.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "task_id": .object(["type": .string("string")]),
        "reminder_id": .object(["type": .string("string")]),
      ]),
      "required": .array([.string("task_id"), .string("reminder_id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    )
  )
}
