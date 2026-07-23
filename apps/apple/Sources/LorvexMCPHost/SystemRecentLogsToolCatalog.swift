import MCP

extension SystemContextToolCatalog {
  static let recentLogsTool = Tool(
    name: "get_recent_logs",
    title: "Get Recent Logs",
    description:
      "Read a merged Lorvex diagnostic stream from error logs, AI changelog, and sync outbox. For the audit trail of what changed on a specific entity, prefer get_ai_changelog (entity/operation filters).",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "limit": .object([
          "type": .string("integer"),
          "description": .string("Maximum merged entries to return, capped at 500"),
        ]),
        "offset": .object([
          "type": .string("integer"),
          "description": .string("Offset into the merged stream"),
        ]),
        "since": .object([
          "type": .string("string"),
          "description": .string("Optional ISO timestamp lower bound"),
        ]),
        "level": .object([
          "type": .string("string"),
          "enum": .array([.string("debug"), .string("info"), .string("warn"), .string("error")]),
          "description": .string("Optional level filter: debug, info, warn, or error"),
        ]),
        "levels": .object([
          "type": .string("array"),
          "items": .object([
            "type": .string("string"),
            "enum": .array([.string("debug"), .string("info"), .string("warn"), .string("error")]),
          ]),
          "description": .string("Optional list of level filters (any of debug, info, warn, error)"),
        ]),
        "source": .object([
          "type": .string("string"),
          "enum": .array([
            .string("error_log"), .string("ai_changelog"), .string("sync_outbox"),
          ]),
          "description": .string("Optional source: error_log, ai_changelog, or sync_outbox"),
        ]),
        "sources": .object([
          "type": .string("array"),
          "items": .object([
            "type": .string("string"),
            "enum": .array([
              .string("error_log"), .string("ai_changelog"), .string("sync_outbox"),
            ]),
          ]),
          "description": .string(
            "Optional list of sources (any of error_log, ai_changelog, sync_outbox)"),
        ]),
        "include_details": .object([
          "type": .string("boolean"),
          "description": .string("Include sanitized error_log details"),
        ]),
        "redact": .object([
          "type": .string("boolean"),
          "description": .string("Redact potential secrets from summaries and details"),
        ]),
      ]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )
}
