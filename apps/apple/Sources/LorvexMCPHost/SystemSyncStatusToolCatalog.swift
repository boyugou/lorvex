import MCP

extension SystemContextToolCatalog {
  static let syncStatusTool = Tool(
    name: "get_sync_status",
    title: "Get Sync Status",
    description:
      "Read local Lorvex sync diagnostics from the database: outbox queue counts, "
      + "device id, and the reseed_required recovery flag. This process can't observe "
      + "the live CloudKit transport, so sync_backend_kind is \"unknown\" here.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([:]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )
}
