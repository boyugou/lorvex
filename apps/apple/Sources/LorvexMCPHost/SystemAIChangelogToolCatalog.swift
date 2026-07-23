import MCP

extension SystemContextToolCatalog {
  static let aiChangelogTool = Tool(
    name: "get_ai_changelog",
    title: "Get AI Changelog",
    description:
      "Read assistant-authored Lorvex audit entries with optional entity, operation, cursor, and pagination filters. For a merged diagnostic stream including errors and the sync outbox, use get_recent_logs.",
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
