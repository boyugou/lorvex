import LorvexCore
import MCP

/// Tool descriptor for exporting Lorvex data as JSON or CSV.
enum DataExportToolCatalog {
  /// Selectable `entities` values: every ``LorvexDataExportCategory`` plus the
  /// `all` sentinel, so the MCP schema stays in lockstep with the core
  /// categories as they grow.
  private static let entityEnum: [Value] =
    LorvexDataExportCategory.allCases.map { .string($0.rawValue) } + [.string("all")]

  static let exportDataTool = Tool(
    name: "export_data",
    title: "Export Data",
    description:
      "Exports Lorvex data (tasks, lists, habits, calendar events, daily reviews, memory, "
      + "preferences, current focus, saved focus schedules) as an embedded JSON or CSV resource. "
      + "Pass `entities` explicitly; use [\"all\"] only when a full export is intended. "
      + "Provider/EventKit blocks inside saved focus schedules honor this device's calendar AI-access "
      + "tier: off omits them, while other tiers retain privacy-neutral occupancy. App-initiated exports "
      + "outside MCP retain every saved block, with provider labels privacy-neutralized. Calendar events "
      + "and daily reviews cover full stored "
      + "history; habits are evaluated for today.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "format": .object([
          "type": .string("string"),
          "enum": .array([.string("json"), .string("csv")]),
          "description": .string("Output format. Defaults to \"json\"."),
        ]),
        "entities": .object([
          "type": .string("array"),
          "items": .object([
            "type": .string("string"),
            "enum": .array(entityEnum),
          ]),
          "description": .string(
            "Entity types to include. Pass [\"all\"] explicitly to export everything."),
        ]),
      ]),
      "required": .array([.string("entities")]),
    ]),
    annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
  )
}
