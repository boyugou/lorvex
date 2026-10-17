import MCP

extension SystemContextToolCatalog {
  static let aiChangelogTool = Tool(
    name: "get_ai_changelog",
    title: "Get AI Changelog",
    description:
      "Read Lorvex audit entries: assistant writes, plus imports and unattributed rows (initiated_by says which), with optional entity, operation, since, and pagination filters. An unrecognized entity_type returns no entries rather than an error. For a merged diagnostic stream including errors and the sync outbox, use get_recent_logs.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "limit": .object([
          "type": .string("integer"),
          "description": .string("Maximum entries to return, capped at 500; defaults to 50"),
        ]),
        "offset": .object([
          "type": .string("integer"),
          "description": .string("Offset for pagination"),
        ]),
        "entity_type": .object([
          "type": .string("string"),
          "description": .string("Optional Lorvex entity type filter"),
        ]),
        "operation": .object([
          "type": .string("string"),
          "description": .string("Optional operation filter"),
        ]),
        "entity_id": .object([
          "type": .string("string"),
          "description": .string("Optional exact entity id filter"),
        ]),
        "since": .object([
          "type": .string("string"),
          "description": .string("Optional timestamp/cursor lower bound"),
        ]),
      ]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )
}
