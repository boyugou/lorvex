import MCP

extension TaskChecklistToolCatalog {
  static let reorderItemsTool = Tool(
    name: "reorder_task_checklist_items",
    title: "Reorder Task Checklist Items",
    description: "Reorder a task's checklist. Supply every current checklist item id exactly once, in the desired order — the id set must be a permutation of the task's existing items (no additions, no omissions). This never adds or removes items; use add_task_checklist_item / remove_task_checklist_item for that. Returns the full updated task.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "task_id": .object(["type": .string("string")]),
        "item_ids": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
        ]),
      ]),
      "required": .array([.string("task_id"), .string("item_ids")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )
}
