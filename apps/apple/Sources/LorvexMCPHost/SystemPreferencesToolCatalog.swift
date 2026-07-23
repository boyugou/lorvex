import MCP

enum SystemPreferencesToolCatalog {}

extension SystemPreferencesToolCatalog {
  static let getAllPreferencesTool = Tool(
    name: "get_all_preferences",
    title: "Get All Preferences",
    description:
      "Returns all configured Lorvex preferences as a key-to-value map. Useful at session start.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([:]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let getPreferenceTool = Tool(
    name: "get_preference",
    title: "Get Preference",
    description: "Read a single preference by key. Returns null when unset.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "key": .object(["type": .string("string")])
      ]),
      "required": .array([.string("key")]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let setPreferenceTool = Tool(
    name: "set_preference",
    title: "Set Preference",
    description: "Set or update a Lorvex preference. Only known configuration keys are accepted; unknown keys are rejected. The value is stored as a JSON string — pass booleans, numbers, and objects as their JSON representation. Common writable keys: working_hours (JSON object with start/end HH:MM), timezone (IANA name e.g. America/New_York), default_list_id, ai_changelog_retention_policy (how long the AI activity log is kept: the string \"maximum\" to retain up to 10,000 entries, the string \"off\" to stop recording and clear existing entries, or a positive integer number of days). Local-only keys (app settings, UI toggles) are filtered from sync. Returns the upserted preference.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "key": .object(["type": .string("string")]),
        "value": .object(["type": .string("string")]),
      ]),
      "required": .array([.string("key"), .string("value")]),
    ]),
    annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
  )

  static let deletePreferenceTool = Tool(
    name: "delete_preference",
    title: "Delete Preference",
    description: "Remove a deletable preference key from the store, returning it to its system default on next read. The synced timezone is the required cross-device calendar-day authority and cannot be deleted; replace it with set_preference instead. Local-only preferences are cleared locally; other synced keys emit a sync tombstone. Returns {key, deleted: true, previous} where previous is the value that was removed (null if the key was unset).",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "key": .object([
          "type": .string("string"),
          "description": .string(
            "Preference key to delete. The required timezone key must be replaced, not deleted."),
        ]),
      ]),
      "required": .array([.string("key")]),
    ]),
    annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false)
  )

  static let completeSetupTool = Tool(
    name: "complete_setup",
    title: "Complete Setup",
    description:
      "Mark Lorvex setup as complete and persist optional working_hours, default_list_id, and timezone preferences.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "working_hours": .object([
          "type": .string("string"),
          "description": .string(
            "Daily working window. Accepts either the hyphen string \"HH:MM-HH:MM\" (e.g. \"09:00-18:00\") or the JSON object string {\"start\":\"09:00\",\"end\":\"18:00\"}. Stored value is the canonical JSON object. End must be after start."),
        ]),
        "default_list_id": .object(["type": .string("string")]),
        "timezone": .object(["type": .string("string")]),
      ]),
    ]),
    annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
  )

}
