import MCP

enum MemoryToolCatalog {
  static let readMemoryTool = Tool(
    name: "read_memory",
    title: "Read Memory",
    description: "Read persistent AI memory. Returns {entries} plus the shared pagination envelope; page with limit/offset following next_offset while truncated is true. Pass key or keys to read specific memory sections. Security: memory content strings are fenced against prompt injection.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "key": .object([
          "type": .string("string"),
          "description": .string("Optional single memory key to read."),
        ]),
        "keys": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
          "description": .string("Optional memory keys to read."),
        ]),
        "limit": .object([
          "type": .string("integer"),
          "description": .string("Maximum entries to return. Defaults to 20 and is capped at 100."),
        ]),
        "offset": .object([
          "type": .string("integer"),
          "description": .string("Zero-based pagination offset. Defaults to 0."),
        ]),
      ]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let writeMemoryTool = Tool(
    name: "write_memory",
    title: "Write Memory",
    description: "Write or update a named section of persistent AI memory. Use to record user preferences, work patterns, list scope summaries, or context that should survive across sessions. Typical keys: user_profile, list_summaries, behavioral_patterns, recent_activity, pending_followups. Returns the written memory entry.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "key": .object([
          "type": .string("string"),
          "description": .string("Memory section key"),
        ]),
        "content": .object([
          "type": .string("string"),
          "description": .string("Memory content"),
        ]),
      ]),
      "required": .array([.string("key"), .string("content")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let renameMemoryTool = Tool(
    name: "rename_memory",
    title: "Rename Memory",
    description: "Atomically rename a memory section from old_key to new_key in one operation, optionally replacing its content — the entry keeps its identity. Prefer this over write_memory(new) + delete_memory(old), which are two separate writes that can leave a duplicate. Rejects renaming onto a different existing key; combine content under one key with write_memory instead. Returns the renamed memory entry.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "old_key": .object([
          "type": .string("string"),
          "description": .string("The existing memory section key to rename."),
        ]),
        "new_key": .object([
          "type": .string("string"),
          "description": .string("The new memory section key."),
        ]),
        "content": .object([
          "type": .string("string"),
          "description": .string(
            "Optional replacement content; omit to keep the existing content."),
        ]),
      ]),
      "required": .array([.string("old_key"), .string("new_key")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )
}
