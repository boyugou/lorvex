import MCP

extension SystemContextToolCatalog {
  static let syncStatusTool = Tool(
    name: "get_sync_status",
    title: "Get Sync Status",
    description:
      "Read Lorvex sync diagnostics: outbox queue counts, device id, the "
      + "reseed_required recovery flag, and what the Lorvex app on this Mac last reported "
      + "about iCloud sync (app_reported_sync: its mode, its state, when a sync pass last "
      + "completed, and when it reported). Sync runs only inside the Lorvex app: when "
      + "app_running is false, changes made here wait in the outbox until the user opens "
      + "Lorvex. sync_backend_kind is \"unknown\" until the app has reported.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([:]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )
}
