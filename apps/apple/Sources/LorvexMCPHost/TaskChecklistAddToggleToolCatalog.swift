import MCP

extension TaskChecklistToolCatalog {
  static let addItemTool = Tool(
    name: "add_task_checklist_item",
    title: "Add Task Checklist Item",
    description: "Append a new checklist step to a task. Use when breaking down a task into sub-steps during planning or when the user provides a list of actions to take. Items are ordered by position (append-only; use reorder_task_checklist_items to rearrange). Returns the full updated task.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "task_id": .object(["type": .string("string")]),
        "text": .object(["type": .string("string")]),
      ]),
      "required": .array([.string("task_id"), .string("text")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )

  static let toggleItemTool = Tool(
    name: "toggle_task_checklist_item",
    title: "Toggle Task Checklist Item",
    description: "Mark a checklist item as completed (true) or incomplete (false). Requires the item's own id (from the checklist_items array in get_task). Returns the full updated task.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "item_id": .object(["type": .string("string")]),
        "completed": .object(["type": .string("boolean")]),
      ]),
      "required": .array([.string("item_id"), .string("completed")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false
    )
  )
}
