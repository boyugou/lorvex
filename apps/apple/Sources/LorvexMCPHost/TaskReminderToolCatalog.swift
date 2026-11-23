import MCP

enum TaskReminderToolCatalog {
  static let addReminderTool = Tool(
    name: "add_task_reminder",
    title: "Add Task Reminder",
    description: "Add a reminder notification to a task at a specific time. Give reminder_at as the date and time on the user's clock, YYYY-MM-DDTHH:MM (e.g. 2026-05-23T10:00 for 10 in the morning); it is read in the time zone get_session_context reports, so there is no offset to work out. An RFC 3339 timestamp with Z or an offset is accepted too. A local time the clocks skip that day is rejected. The app schedules a notification at that time. A task can have several reminders. Returns the full updated task; each of its reminders carries reminder_at (UTC) and, once the user's time zone is set, local_time and timezone.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "task_id": .object(["type": .string("string")]),
        "reminder_at": .object([
          "type": .string("string"),
          "description": .string("Local date and time, YYYY-MM-DDTHH:MM (2026-05-23T10:00), or an RFC 3339 timestamp with Z or an offset."),
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
    description: "Remove a specific reminder from a task. Requires both task_id and the reminder's own id (from the reminders array in get_task or list_tasks). Also cancels the scheduled notification on the app's next scheduling pass. A reminder_id that is not one of this task's reminders is ignored, and the task is returned unchanged. Returns the full updated task.",
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
