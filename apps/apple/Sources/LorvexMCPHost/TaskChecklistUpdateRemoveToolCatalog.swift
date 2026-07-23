import MCP

extension TaskChecklistToolCatalog {
  static let updateItemTool = Tool(
    name: "update_task_checklist_item",
    title: "Update Task Checklist Item",
    description: "Update the text of one checklist item and return the enriched task.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "item_id": .object(["type": .string("string")]),
        "text": .object(["type": .string("string")]),
      ]),
      "required": .array([.string("item_id"), .string("text")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let removeItemTool = Tool(
    name: "remove_task_checklist_item",
    title: "Remove Task Checklist Item",
    description: "Remove a checklist item from a Lorvex task. Returns the enriched task.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "item_id": .object(["type": .string("string")])
      ]),
      "required": .array([.string("item_id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    )
  )
}
