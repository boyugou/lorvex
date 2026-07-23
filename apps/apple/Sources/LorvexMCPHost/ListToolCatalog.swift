import MCP

extension ListHabitToolCatalog {
  static let getListsTool = Tool(
    name: "get_lists",
    title: "Get Lists",
    description: "Return all active user-created task lists with open and total task counts. Use to see all lists, look up list IDs before moving tasks, or identify stalled lists during review. Returns {lists} where each entry includes id, name, open_count, total_count, and archived. Pass include_archived: true to also return archived lists (those retired via archive_list) — needed to find a list's id before unarchive_list.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "include_archived": .object([
          "type": .string("boolean"),
          "description": .string("Also return archived lists. Default false (active lists only)."),
        ])
      ]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
  )

  static let createListTool = Tool(
    name: "create_list",
    title: "Create List",
    description: "Create a new task list. Use when the user describes a new area to organize tasks into (a project, a context, a life area). Supply name (required), an optional description, and optional appearance: icon (an SF Symbol name such as 'briefcase', 'house', 'cart') and color (a #RRGGBB hex such as '#22C55E'). The list color drives its sidebar accent, header, and progress bar. Optional ai_notes records AI-only scope/profile metadata for the list. Returns the full created list object including its newly assigned id.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "original_id": .object([
          "type": .string("string"),
          "description": .string(
            "Restore this list at a caller-supplied id instead of minting a new one, so an exported list's tasks (which reference it by id) re-home to it on re-create. Omit for an ordinary new list."),
        ]),
        "name": .object([
          "type": .string("string"),
          "description": .string("List name"),
        ]),
        "description": .object([
          "type": .string("string"),
          "description": .string("Optional list description"),
        ]),
        "icon": .object([
          "type": .string("string"),
          "description": .string("Optional SF Symbol name (e.g. 'briefcase', 'house'). Omit for the default folder glyph."),
        ]),
        "color": .object([
          "type": .string("string"),
          "description": .string("Optional #RRGGBB hex accent (e.g. '#22C55E'). Omit for the app accent."),
        ]),
        "ai_notes": .object([
          "type": .string("string"),
          "description": .string("Optional AI-only scope/profile notes for the list (AI-authored; shown read-only, never human-editable). Record what the list is for, its boundaries, or planning context."),
        ]),
      ]),
      "required": .array([.string("name")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )
}
