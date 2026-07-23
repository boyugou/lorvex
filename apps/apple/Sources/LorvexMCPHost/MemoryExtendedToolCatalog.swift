import MCP

enum MemoryExtendedToolCatalog {
  static let deleteMemoryTool = Tool(
    name: "delete_memory",
    title: "Delete Memory",
    description: "Permanently deletes an AI-writable memory entry by key. Returns {deleted, id, previous, key} where previous is the removed memory entry (null on a no-op).",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "key": .object([
          "type": .string("string"),
          "description": .string("Memory section key to delete"),
        ])
      ]),
      "required": .array([.string("key")]),
    ]),
    annotations: .init(
      readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false)
  )
}
