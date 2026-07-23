import MCP

extension TaskMutationToolCatalog {
  static let setTaskAINotesTool = Tool(
    name: "set_task_ai_notes",
    title: "Set Task AI Context",
    description: "Replace the assistant-maintained context block for one task without changing canonical task notes. Use this for the current recommendation, caveat, operating instruction, or short reasoning a future assistant should preserve. Pass an empty notes string to clear the block. Returns the full updated task object.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "task_id": .object([
          "type": .string("string"),
          "description": .string("Task id"),
        ]),
        "notes": .object([
          "type": .string("string"),
          "description": .string("Current assistant context for this task; empty clears it"),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("task_id"), .string("notes")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )
}
