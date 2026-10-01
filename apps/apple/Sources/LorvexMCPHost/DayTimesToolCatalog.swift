import MCP

extension DayPlanningToolCatalog {
  static let proposeDailyScheduleTool = Tool(
    name: "propose_daily_schedule",
    title: "Propose Daily Schedule",
    description:
      "Suggest times for a day's tasks without saving anything. Each task on the day's Today "
      + "list, in its order (started tasks first, then by priority and due date), takes the "
      + "earliest free working time around calendar events that holds it, so a short task can "
      + "fill a gap a longer one did not fit; a task without an estimate takes 30 minutes. A "
      + "ten-minute break follows each task when it fits. For today the suggestion "
      + "starts at the current time, rounded up to five minutes: a task whose time is under way "
      + "keeps it, work whose time passed unfinished is placed again, and tasks that no longer "
      + "fit come back in unscheduled. A day with no open tasks returns no placements and still "
      + "lists its events. Returns {date, working_hours: {start, end}, "
      + "available_minutes, placements: [{task, start_time, end_time}], events: [{start_time, "
      + "end_time, title, event_id, source}], unscheduled}; a placement's start_time/end_time is "
      + "the suggested time, and an event's title is null when the calendar setting shares only "
      + "busy time. Most people never time their day; offer this when the user asks for a "
      + "timetable, then call save_daily_schedule with the times they accept.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD date to plan. Defaults to today."),
        ]),
        "working_hours_start": .object([
          "type": .string("string"),
          "description": .string(
            "Start of the working window for this suggestion, HH:MM (24-hour). Defaults to the user's working hours (09:00 when unset)."
          ),
        ]),
        "working_hours_end": .object([
          "type": .string("string"),
          "description": .string(
            "End of the working window for this suggestion, HH:MM (24-hour). Defaults to the user's working hours (18:00 when unset)."
          ),
        ]),
        "include_calendar_events": .object([
          "type": .string("boolean"),
          "description": .string(
            "Defaults to true: plan around the day's calendar events. False plans as if the calendar were empty."
          ),
        ]),
      ]),
    ]),
    annotations: .init(
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )

  static let saveDailyScheduleTool = Tool(
    name: "save_daily_schedule",
    title: "Save Daily Schedule",
    description:
      "Save the times of a day's unfinished tasks, replacing the day's times. Each listed task "
      + "is planned for the date (planned_date) and takes its time; every other unfinished task "
      + "timed on that date loses its time and stays on the day. Finished tasks keep their times "
      + "as the day's record. An empty times array clears the day's times. Returns {date, "
      + "timed_tasks, cleared_tasks}: every task timed on the date in start order, and the tasks "
      + "the save took a time from.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD date the times are for."),
        ]),
        "times": .object([
          "type": .string("array"),
          "maxItems": .int(MCPBatchLimits.maxItems),
          "description": .string(
            "The day's timed tasks. Each task is open or started and appears once."),
          "items": .object([
            "type": .string("object"),
            "properties": .object([
              "task_id": .object([
                "type": .string("string"),
                "description": .string("The task that takes this time."),
              ]),
              "start_time": .object([
                "type": .string("string"),
                "description": .string("Start, HH:MM (24-hour)."),
              ]),
              "end_time": .object([
                "type": .string("string"),
                "description": .string(
                  "End, HH:MM (24-hour), after the start; 24:00 is the midnight that ends the day."
                ),
              ]),
            ]),
            "required": .array([.string("task_id"), .string("start_time"), .string("end_time")]),
          ]),
        ]),
      ]),
      "required": .array([.string("date"), .string("times")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )

  static let getDailyScheduleTool = Tool(
    name: "get_daily_schedule",
    title: "Get Daily Schedule",
    description:
      "Read the times on a date (defaults to today): {date, timed_tasks}, every task timed on "
      + "that day in start order, finished ones included. An empty timed_tasks means the day has "
      + "no times. Check this before proposing times so you do not overwrite times the user set.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD date to read. Defaults to today."),
        ])
      ]),
    ]),
    annotations: .init(
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )
}
