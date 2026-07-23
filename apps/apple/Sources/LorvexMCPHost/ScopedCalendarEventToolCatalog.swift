import MCP

extension CalendarLinksToolCatalog {
  private static let scopeProperty: Value = .object([
    "type": .string("string"),
    "enum": .array([
      .string("all_in_series"),
      .string("this_only"),
      .string("this_and_following"),
    ]),
    "description": .string(
      "all_in_series: edit/delete the entire recurring series. "
      + "this_only: store a synced decision for this occurrence; edit replaces it and delete cancels it. "
      + "this_and_following: truncate the series before occurrence_date, edit creates a new series from occurrence_date."
    ),
  ])

  static let editScopedEventTool = Tool(
    name: "edit_scoped_calendar_event",
    title: "Edit Scoped Calendar Event",
    description: "Edit a recurring calendar event with scope control: all_in_series patches the whole series, this_only stores a replacement decision for one occurrence, and this_and_following splits the series at occurrence_date and creates a replacement series. Returns {original_event?, replacement_event?, noop}.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "event_id": .object(["type": .string("string")]),
        "occurrence_date": .object(["type": .string("string"), "description": .string("YYYY-MM-DD of the occurrence to scope the edit to")]),
        "scope": scopeProperty,
        "title": .object(["type": .string("string")]),
        "start_date": .object(["type": .string("string")]),
        "end_date": .object(["type": .string("string")]),
        "start_time": .object(["type": .string("string")]),
        "end_time": .object(["type": .string("string")]),
        "all_day": .object(["type": .string("boolean")]),
        "location": .object(["type": .string("string")]),
        "notes": .object(["type": .string("string")]),
        "recurrence": RecurrenceRuleSchema.calendarRecurrencePatchProperty,
        "timezone": .object(["type": .string("string")]),
        "url": .object(["type": .string("string")]),
        "color": .object(["type": .string("string")]),
        "event_type": .object([
          "type": .string("string"),
          "enum": .array([
            .string("event"), .string("birthday"), .string("anniversary"), .string("memorial"),
          ]),
        ]),
        "person_name": .object(["type": .string("string")]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("event_id"), .string("occurrence_date"), .string("scope")]),
    ]),
    annotations: .init(
      readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)
  )

  static let deleteScopedEventTool = Tool(
    name: "delete_scoped_calendar_event",
    title: "Delete Scoped Calendar Event",
    description: "Delete a recurring calendar event with scope control: all_in_series deletes the entire series, this_only stores a cancellation decision for one occurrence, and this_and_following truncates the series before occurrence_date or deletes it if it collapses. Returns {previous?, noop} where previous is the surviving/modified series event (null when the whole series is gone).",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "event_id": .object(["type": .string("string")]),
        "occurrence_date": .object(["type": .string("string"), "description": .string("YYYY-MM-DD of the occurrence to scope the delete to")]),
        "scope": scopeProperty,
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("event_id"), .string("occurrence_date"), .string("scope")]),
    ]),
    annotations: .init(
      readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false)
  )
}
