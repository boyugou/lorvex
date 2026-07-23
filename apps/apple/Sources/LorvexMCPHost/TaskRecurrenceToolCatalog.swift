import MCP

enum TaskRecurrenceToolCatalog {
  static let setRecurrenceTool = Tool(
    name: "set_task_recurrence",
    title: "Set Task Recurrence",
    description:
      "Set a recurring schedule on a task. freq is required (DAILY/WEEKLY/MONTHLY/YEARLY). Common examples: daily task = {freq:DAILY}, every weekday = {freq:WEEKLY,byday:[MO,TU,WE,TH,FR]}, weekly on Monday = {freq:WEEKLY,byday:[MO]}, first Monday of month = {freq:MONTHLY,byday:[MO],bysetpos:[1]}, monthly on the 1st and 15th = {freq:MONTHLY,bymonthday:[1,15]}. bymonthday is an array of ints in ±1..31 (negative counts from month end, -1 = last day). anchor defaults to \"schedule\" (fixed calendar cadence); set anchor=\"completion\" to schedule the next occurrence INTERVAL units after the task is completed (e.g. water the plant 3 days after you last did) — completion-anchored rules must omit byday/bymonth/bymonthday/bysetpos/wkst. Completing or cancelling a recurring task spawns the next occurrence automatically. Returns the updated task.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "task_id": .object(["type": .string("string")]),
        "recurrence": RecurrenceRuleSchema.taskRuleProperty,
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("task_id"), .string("recurrence")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )

  static let removeRecurrenceTool = Tool(
    name: "remove_task_recurrence",
    title: "Remove Task Recurrence",
    description: "Remove the recurrence rule and skip dates from a task. Returns the updated task.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "task_id": .object(["type": .string("string")]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("task_id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: false
    )
  )

  static let addExceptionTool = Tool(
    name: "add_task_recurrence_exception",
    title: "Add Task Recurrence Exception",
    description: "Add an exception (skip) date to a recurring task. Returns the updated task.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "task_id": .object(["type": .string("string")]),
        "occurrence_date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD occurrence to skip."),
        ]),
      ]),
      "required": .array([.string("task_id"), .string("occurrence_date")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )

  static let removeExceptionTool = Tool(
    name: "remove_task_recurrence_exception",
    title: "Remove Task Recurrence Exception",
    description: "Remove a previously added skip date from a recurring task. Returns the updated task.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "task_id": .object(["type": .string("string")]),
        "occurrence_date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD occurrence to restore."),
        ]),
      ]),
      "required": .array([.string("task_id"), .string("occurrence_date")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )
}
