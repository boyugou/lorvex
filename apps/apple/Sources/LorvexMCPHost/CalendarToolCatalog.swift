import MCP

enum CalendarToolCatalog {
  static let timelineTool = Tool(
    name: "get_calendar_timeline",
    title: "Get Calendar Timeline",
    description: "Read calendar events in a date range. The result includes Lorvex-owned events plus provider/EventKit mirror events (read-only external calendar events) subject to the caller's calendar AI-access privacy tier: fullDetails returns full event details, busyOnly returns opaque busy blocks, off omits provider events (only Lorvex-native items remain). Default event rows are compact and omit null/heavy fields; use shape=full, fields, or include for details, attendees, or recurrence. id uniquely identifies the rendered row; event_id is the stable source address. Use a canonical event_id with canonical mutation/link tools, or a provider event_id as provider_event_id together with provider_source for the device-local provider-link tool.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "from": .object([
          "type": .string("string"),
          "description": .string("Inclusive lower bound date, YYYY-MM-DD"),
        ]),
        "to": .object([
          "type": .string("string"),
          "description": .string("Inclusive upper bound date, YYYY-MM-DD"),
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
        "limit": .object([
          "type": .string("integer"),
          "description": .string("Maximum events to return, 1-500. Defaults to 100."),
        ]),
        "offset": .object([
          "type": .string("integer"),
          "description": .string("Zero-based event offset for paging through a large date range."),
        ]),
      ]),
      "required": .array([.string("from"), .string("to")]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let createEventTool = Tool(
    name: "create_calendar_event",
    title: "Create Calendar Event",
    description: "Create a Lorvex-owned canonical calendar event. Lorvex events are editable, synced, and support scoped recurring-occurrence edits and cancellations — unlike provider-mirror events from EventKit which are read-only. Optional fields: end_date, start_time, end_time, location, notes, recurrence (a typed recurrence object — the same shape set_task_recurrence takes, minus anchor), timezone, url, color, event_type (event/birthday/anniversary/memorial), person_name, attendees, original_id (restore at a caller-supplied id for id-preserving re-create). Returns the created event.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "original_id": .object([
          "type": .string("string"),
          "description": .string(
            "Restore this event at a caller-supplied id instead of minting a new one, so exported task↔event links resolve on re-create. Omit for an ordinary new event."),
        ]),
        "title": .object(["type": .string("string")]),
        "start_date": .object([
          "type": .string("string"),
          "description": .string("YYYY-MM-DD"),
        ]),
        "end_date": .object([
          "type": .string("string"),
          "description": .string(
            "YYYY-MM-DD. Set to a date after start_date for a multi-day event; omit for a single-day event."),
        ]),
        "start_time": .object([
          "type": .string("string"),
          "description": .string("HH:MM. Omit for all-day events."),
        ]),
        "end_time": .object(["type": .string("string")]),
        "all_day": .object(["type": .string("boolean")]),
        "recurrence": RecurrenceRuleSchema.calendarRecurrenceProperty,
        "timezone": .object([
          "type": .string("string"),
          "description": .string("Optional IANA timezone, e.g. America/Los_Angeles."),
        ]),
        "location": .object(["type": .string("string")]),
        "notes": .object(["type": .string("string")]),
        "url": .object(["type": .string("string")]),
        "color": .object([
          "type": .string("string"),
          "description": .string("Optional hex color."),
        ]),
        "event_type": .object([
          "type": .string("string"),
          "enum": .array([
            .string("event"), .string("birthday"), .string("anniversary"), .string("memorial"),
          ]),
        ]),
        "person_name": .object(["type": .string("string")]),
        "attendees": .object([
          "type": .string("array"),
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
      "required": .array([.string("title"), .string("start_date")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let batchCreateEventsTool = Tool(
    name: "batch_create_calendar_events",
    title: "Batch Create Calendar Events",
    description: "Create multiple Lorvex calendar events in one call. Each event uses the same fields as create_calendar_event (including original_id for id-preserving re-create). Use when importing a schedule, creating a series of related meetings, or setting up a week's worth of time blocks. Validates and creates each event independently: a bad event is reported and the rest still land. Returns {results, count, skipped} where results is the full created event object for each event and skipped is per-item failures as [{id, reason}].",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "events": .object([
          "type": .string("array"),
          "maxItems": .int(MCPBatchLimits.maxItems),
          "description": .string("Array of event objects; each has the same fields as create_calendar_event."),
          "items": .object([
            "type": .string("object"),
            "properties": .object([
              "original_id": .object([
                "type": .string("string"),
                "description": .string(
                  "Restore this event at a caller-supplied id (id-preserving re-create) instead of minting a new one."),
              ]),
              "title": .object(["type": .string("string")]),
              "start_date": .object(["type": .string("string")]),
              "end_date": .object(["type": .string("string")]),
              "start_time": .object(["type": .string("string")]),
              "end_time": .object(["type": .string("string")]),
              "all_day": .object(["type": .string("boolean")]),
              "location": .object(["type": .string("string")]),
              "notes": .object(["type": .string("string")]),
              "url": .object(["type": .string("string")]),
              "color": .object([
                "type": .string("string"),
                "description": .string("Optional hex color."),
              ]),
              "recurrence": RecurrenceRuleSchema.calendarRecurrenceProperty,
              "timezone": .object(["type": .string("string")]),
              "event_type": .object([
                "type": .string("string"),
                "enum": .array([
                  .string("event"), .string("birthday"), .string("anniversary"), .string("memorial"),
                ]),
              ]),
              "person_name": .object(["type": .string("string")]),
              "attendees": .object([
                "type": .string("array"),
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
            "required": .array([.string("title"), .string("start_date")]),
          ]),
          "minItems": .int(1),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("events")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )
}
