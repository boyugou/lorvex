import MCP

/// Tool descriptor for RFC 5545 ICS export of the Lorvex canonical calendar.
enum IcsExportToolCatalog {
  static let exportCalendarIcsTool = Tool(
    name: "export_calendar_ics",
    title: "Export Calendar ICS",
    description:
      "Returns canonical Lorvex calendar events in the date range as an embedded RFC 5545 ICS "
      + "resource suitable for import into any calendar application. `from` and `to` are inclusive "
      + "YYYY-MM-DD dates; both default to today…today+30d when omitted.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "from": .object([
          "type": .string("string"),
          "description": .string("Start date (YYYY-MM-DD, inclusive). Defaults to today."),
        ]),
        "to": .object([
          "type": .string("string"),
          "description": .string(
            "End date (YYYY-MM-DD, inclusive). Defaults to 30 days from today."),
        ]),
      ]),
      "required": .array([]),
    ]),
    annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
  )
}
