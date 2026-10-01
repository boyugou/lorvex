import MCP

extension SystemContextToolCatalog {
  static let guideTool = Tool(
    name: "get_guide",
    title: "Get Guide",
    description:
      "Read contextual Lorvex guidance for the current setup, task, planning, preference, review, or data state.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "topic": .object([
          "type": .string("string"),
          "description": .string(
            "Optional topic: overview, getting_started, task_management, planning, lists, weekly_review, preferences, data_and_export"
          ),
        ])
      ]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )
}
