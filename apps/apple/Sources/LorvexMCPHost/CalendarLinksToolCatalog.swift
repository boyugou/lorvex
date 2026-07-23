import MCP

/// Tool descriptors for the canonical calendar-event update/delete/search
/// operations plus task <-> event link management:
/// `update_calendar_event` / `delete_calendar_event` /
/// `search_calendar_events` / `link_task_to_event` / `unlink_task_from_event`
/// (canonical, synced) / `link_task_to_provider_event` /
/// `unlink_task_from_provider_event` (device-local) /
/// `get_linked_events_for_task` / `get_linked_tasks_for_event`.
enum CalendarLinksToolCatalog {
  static let updateEventTool = Tool(
    name: "update_calendar_event",
    title: "Update Calendar Event",
    description:
      "Patch a Lorvex-owned canonical calendar event. event_id is the stable address returned on every Lorvex-owned row. For a recurring event this updates the whole series; use edit_scoped_calendar_event for this occurrence or this-and-following. Provider/EventKit rows are read-only. Omitted fields are left untouched. Returns the updated calendar event.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "event_id": .object([
          "type": .string("string"),
          "description": .string(
            "Stable canonical event address returned as event_id by calendar read tools."),
        ]),
        "title": .object(["type": .string("string")]),
        "start_date": .object(["type": .string("string")]),
        "end_date": .object([
          "type": .string("string"),
          "description": .string(
            "YYYY-MM-DD. Set to a date after start_date for a multi-day event."),
        ]),
        "start_time": .object(["type": .string("string")]),
        "end_time": .object(["type": .string("string")]),
        "all_day": .object(["type": .string("boolean")]),
        "recurrence": RecurrenceRuleSchema.calendarRecurrencePatchProperty,
        "timezone": .object(["type": .string("string")]),
        "location": .object(["type": .string("string")]),
        "notes": .object(["type": .string("string")]),
        "url": .object(["type": .string("string")]),
        "color": .object(["type": .string("string")]),
        "event_type": .object([
          "type": .string("string"),
          "enum": .array([
            .string("event"), .string("birthday"), .string("anniversary"), .string("memorial"),
          ]),
        ]),
        "person_name": .object(["type": .string("string")]),
        "attendees": .object([
          "type": .array([.string("array"), .string("null")]),
          "items": .object([
            "type": .string("object"),
            "description": .string(
              "A lightweight {name?, email?} annotation — no RSVP status. Each attendee must carry an email, a name, or both; a fully empty attendee is rejected."),
            "properties": .object([
              "email": .object(["type": .string("string")]),
              "name": .object(["type": .string("string")]),
            ]),
          ]),
        ]),
      ]),
      "required": .array([.string("event_id")]),
    ]),
    annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
  )

  static let deleteEventTool = Tool(
    name: "delete_calendar_event",
    title: "Delete Calendar Event",
    description: "Delete a Lorvex-owned canonical calendar event. event_id is the stable address returned on every Lorvex-owned row. For a recurring event this deletes the whole series; use delete_scoped_calendar_event for this occurrence or this-and-following. Provider/EventKit mirrors are read-only. Also emits tombstone records so the deletion syncs. Returns {deleted, id, previous} where deleted reflects the real outcome (false with previous null when no such event exists) and previous is the removed event object.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "event_id": .object([
          "type": .string("string"),
          "description": .string(
            "Stable canonical event address returned as event_id by calendar read tools."),
        ])
      ]),
      "required": .array([.string("event_id")]),
    ]),
    annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false)
  )

  static let searchEventsTool = Tool(
    name: "search_calendar_events",
    title: "Search Calendar Events",
    description: "Search calendar events by title substring across Lorvex-owned events plus provider/EventKit mirror events. Provider events are matched only at the caller's fullDetails calendar AI-access privacy tier; busyOnly and off omit them entirely (searching redacted busy blocks would leak the detail the tier withholds), leaving only Lorvex-native events. Optionally filter by date range (from/to in YYYY-MM-DD). Default event rows are compact; use shape=full, fields, or include to request heavier detail. id uniquely identifies the rendered row; event_id is the stable source address. Use a canonical event_id with canonical mutation/link tools, or a provider event_id as provider_event_id together with provider_source for the device-local provider-link tool. Returns {events} plus the shared pagination envelope (total_matching is null — the merged result has no cheap count); page with limit/offset following next_offset while truncated is true.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "query": .object(["type": .string("string")]),
        "from": .object(["type": .string("string")]),
        "to": .object(["type": .string("string")]),
        "limit": .object([
          "type": .string("integer"),
          "description": .string("Maximum events to return, capped at 500. Default 50."),
        ]),
        "offset": .object([
          "type": .string("integer"),
          "description": .string("Zero-based pagination offset. Defaults to 0."),
        ]),
        "shape": .object([
          "type": .string("string"),
          "enum": .array([.string("compact"), .string("full")]),
          "description": .string(
            "Event row shape. compact is the default and omits null/heavy fields; full preserves complete event rows."),
        ]),
        "include_nulls": .object([
          "type": .string("boolean"),
          "description": .string(
            "Include explicit null values in event rows. Defaults to false for compact and true for full."),
        ]),
        "fields": .object([
          "type": .string("array"),
          "items": .object([
            "type": .string("string"),
            "enum": .array(CalendarEventValueOptions.fieldNames.map(Value.string)),
          ]),
          "description": .string(
            "Exact event fields to return. id and event_id are always included. Recurring canonical rows also include recurrence-address metadata automatically. Overrides the compact/full field set."),
        ]),
        "include": .object([
          "type": .string("array"),
          "items": .object([
            "type": .string("string"),
            "enum": .array(CalendarEventValueOptions.includeValues.map(Value.string)),
          ]),
          "description": .string(
            "Additional event field groups or field names to include with compact rows: details, attendees, recurrence, time, metadata."),
        ]),
      ]),
      "required": .array([.string("query")]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let linkTaskToProviderEventTool = Tool(
    name: "link_task_to_provider_event",
    title: "Link Task to Provider Event",
    description: "Associate a task with an external provider calendar event (e.g. an EventKit meeting). This creates a bidirectional link so the task shows up when inspecting the meeting and the meeting shows up on the task. The link is device-local (provider identities are device-specific). Returns the created link.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "task_id": .object(["type": .string("string")]),
        "provider_event_id": .object(["type": .string("string")]),
        "provider_source": .object(["type": .string("string")]),
      ]),
      "required": .array([
        .string("task_id"), .string("provider_event_id"), .string("provider_source"),
      ]),
    ]),
    annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
  )

  static let linkTaskToEventTool = Tool(
    name: "link_task_to_event",
    title: "Link Task to Calendar Event",
    description: "Create the canonical bidirectional link between a Lorvex task and a Lorvex-owned calendar event, so the task appears when inspecting the event (get_linked_tasks_for_event) and the event on the task (get_linked_events_for_task). Unlike link_task_to_provider_event — which links to a device-local EventKit meeting — this canonical link syncs across devices. Both ids must reference existing Lorvex records. Idempotent: re-linking the same pair is a no-op. Returns the link.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "task_id": .object(["type": .string("string")]),
        "event_id": .object([
          "type": .string("string"),
          "description": .string("Id of a Lorvex-owned canonical calendar event."),
        ]),
      ]),
      "required": .array([.string("task_id"), .string("event_id")]),
    ]),
    annotations: .init(
      readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)
  )

  static let unlinkTaskFromEventTool = Tool(
    name: "unlink_task_from_event",
    title: "Unlink Task from Calendar Event",
    description: "Remove the canonical bidirectional link between a Lorvex task and a Lorvex-owned calendar event — the counterpart to link_task_to_event. Use to undo a mis-link without deleting the task or event. Unlike unlink_task_from_provider_event, which drops a device-local EventKit association, this removal syncs across devices. Returns {deleted, task_id, calendar_event_id} where deleted reflects whether a link was actually removed (false on a no-op when the pair was not linked).",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "task_id": .object(["type": .string("string")]),
        "event_id": .object([
          "type": .string("string"),
          "description": .string("Id of a Lorvex-owned canonical calendar event."),
        ]),
      ]),
      "required": .array([.string("task_id"), .string("event_id")]),
    ]),
    annotations: .init(
      readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false)
  )

  static let unlinkTaskFromProviderEventTool = Tool(
    name: "unlink_task_from_provider_event",
    title: "Unlink Task from Provider Event",
    description: "Remove the association between a task and a provider calendar event. Use when a meeting was cancelled or the link was created by mistake. Returns {deleted, task_id, provider_event_id} where deleted reflects whether a link was actually removed (false on a no-op).",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "task_id": .object(["type": .string("string")]),
        "provider_event_id": .object(["type": .string("string")]),
      ]),
      "required": .array([.string("task_id"), .string("provider_event_id")]),
    ]),
    annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false)
  )

  static let linkedEventsForTaskTool = Tool(
    name: "get_linked_events_for_task",
    title: "Get Linked Events for Task",
    description: "Return all calendar events associated with a task: Lorvex-owned events plus provider/EventKit mirror links subject to the caller's calendar AI-access privacy tier: fullDetails returns full event details, busyOnly returns opaque busy blocks, off omits provider events (only Lorvex-native items remain). Default event rows are compact; use shape=full, fields, or include to request heavier detail. id uniquely identifies the rendered row; event_id is the stable canonical-series or provider source address. Returns {events}.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "task_id": .object(["type": .string("string")]),
        "shape": .object([
          "type": .string("string"),
          "enum": .array([.string("compact"), .string("full")]),
          "description": .string(
            "Event row shape. compact is the default and omits null/heavy fields; full preserves complete event rows."),
        ]),
        "include_nulls": .object([
          "type": .string("boolean"),
          "description": .string(
            "Include explicit null values in event rows. Defaults to false for compact and true for full."),
        ]),
        "fields": .object([
          "type": .string("array"),
          "items": .object([
            "type": .string("string"),
            "enum": .array(CalendarEventValueOptions.fieldNames.map(Value.string)),
          ]),
          "description": .string(
            "Exact event fields to return. id and event_id are always included. Recurring canonical rows also include recurrence-address metadata automatically. Overrides the compact/full field set."),
        ]),
        "include": .object([
          "type": .string("array"),
          "items": .object([
            "type": .string("string"),
            "enum": .array(CalendarEventValueOptions.includeValues.map(Value.string)),
          ]),
          "description": .string(
            "Additional event field groups or field names to include with compact rows: details, attendees, recurrence, time, metadata."),
        ]),
      ]),
      "required": .array([.string("task_id")]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let linkedTasksForEventTool = Tool(
    name: "get_linked_tasks_for_event",
    title: "Get Linked Tasks for Event",
    description: "Return all tasks linked to a calendar event. Use when reviewing a meeting to see which action items are associated with it. Returns {tasks}.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "event_id": .object(["type": .string("string")])
      ]),
      "required": .array([.string("event_id")]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let removeEventExceptionTool = Tool(
    name: "remove_calendar_event_exception",
    title: "Remove Calendar Event Exception",
    description: "Restore a previously skipped occurrence of a recurring calendar event by storing an inherit decision for that occurrence. Use when a cancelled occurrence is back on. Returns the updated calendar event.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "event_id": .object([
          "type": .string("string"),
          "description": .string("ID of the recurring calendar event"),
        ]),
        "occurrence_date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD occurrence to restore"),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("event_id"), .string("occurrence_date")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )

  static let addEventExceptionTool = Tool(
    name: "add_calendar_event_exception",
    title: "Add Calendar Event Exception",
    description: "Skip a specific occurrence of a recurring calendar event by storing a synced cancellation decision. Use when one occurrence of a recurring meeting is cancelled without cancelling the whole series. Returns the updated calendar event.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "event_id": .object([
          "type": .string("string"),
          "description": .string("ID of the recurring calendar event"),
        ]),
        "occurrence_date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD occurrence to skip"),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("event_id"), .string("occurrence_date")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )
}
