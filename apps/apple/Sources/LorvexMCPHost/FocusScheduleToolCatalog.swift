import MCP

extension FocusToolCatalog {
  static let proposeDailyScheduleTool = Tool(
    name: "propose_daily_schedule",
    title: "Propose Daily Schedule",
    description:
      "Generate a time-blocked focus schedule for the current focus tasks. "
      + "Optionally pass working_hours_start / working_hours_end (HH:MM, 24-hour) and "
      + "include_calendar_events (bool) to let the assistant honour the user's actual "
      + "working window and block out existing calendar commitments.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD focus date"),
        ]),
        "working_hours_start": .object([
          "type": .string("string"),
          "description": .string("Start of the working window, HH:MM (24-hour). Defaults to 09:00."),
        ]),
        "working_hours_end": .object([
          "type": .string("string"),
          "description": .string("End of the working window, HH:MM (24-hour). Defaults to 18:00."),
        ]),
        "include_calendar_events": .object([
          "type": .string("boolean"),
          "description": .string(
            "When true, fetch calendar events for the date and treat them as immovable blocks."
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

  static let saveFocusScheduleTool = Tool(
    name: "save_focus_schedule",
    title: "Save Focus Schedule",
    description: "Persist a time-blocked focus schedule and apply task blocks to current focus. Returns the saved focus schedule, including a current_focus field carrying the merged focus plan.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD focus date"),
        ]),
        "blocks": .object([
          "type": .string("array"),
          "description": .string("Ordered list of time blocks for the day."),
          "items": .object([
            "type": .string("object"),
            "properties": .object([
              "task_id": .object([
                "type": .string("string"),
                "description": .string(
                  "Task id this block is allocated to. Omit for non-task blocks."
                ),
              ]),
              "start_time": .object([
                "type": .string("string"),
                "description": .string("Block start, HH:MM (24-hour)."),
              ]),
              "end_time": .object([
                "type": .string("string"),
                "description": .string("Block end, HH:MM (24-hour)."),
              ]),
              "block_type": .object([
                "type": .string("string"),
                "enum": .array([.string("task"), .string("buffer"), .string("event")]),
                "description": .string(
                  "Defaults to task. A task block requires task_id; an event block may "
                    + "carry a canonical event_id; a buffer carries neither."
                ),
              ]),
              "event_id": .object([
                "type": .string("string"),
                "description": .string(
                  "Calendar event id when block_type is event, otherwise omit."
                ),
              ]),
              "event_source": .object([
                "type": .string("string"),
                "enum": .array([
                  .string("canonical"), .string("provider"), .string("freeform"),
                ]),
                "description": .string(
                  "Required for event blocks. Use canonical for a Lorvex calendar event, "
                    + "provider for a block proposed from a device calendar, or freeform for "
                    + "an authored label with no calendar identity."
                ),
              ]),
              "title": .object([
                "type": .string("string"),
                "description": .string("Human-readable label for non-task blocks."),
              ]),
            ]),
            "required": .array([.string("start_time"), .string("end_time")]),
          ]),
        ]),
        "rationale": .object([
          "type": .string("string"),
          "description": .string("Optional schedule rationale"),
        ]),
      ]),
      "required": .array([.string("date"), .string("blocks")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )
}
