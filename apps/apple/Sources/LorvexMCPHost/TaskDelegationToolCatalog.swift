import LorvexDomain
import MCP

extension TaskMutationToolCatalog {
  static let delegateTaskTool = Tool(
    name: "delegate_task",
    title: "Hand Task to Assistant",
    description:
      "Record that the user handed a task to you, their assistant, so it waits for you to work on it. Use it when the user says a task is yours to do (\"you handle this\", \"find me a slot\"), or when you take a task on in conversation. Pass the user's words as request when they ask for more than the task itself says. "
      + "Only an open or started task outside the Trash can be handed over. Repeating it with the same request changes nothing. On a task you already hold, a different request replaces the earlier one, and calling it with no request removes the earlier one. On a task you handed back, it hands the task to you again. "
      + "Find the tasks waiting for you with list_tasks (delegation assistant), work on them with your other tools, then call return_task. Returns the full updated task object.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "id": .object([
          "type": .string("string"),
          "description": .string("Task id"),
        ]),
        "request": .object([
          "type": .string("string"),
          "description": .string(
            "What the user asked you to do, in their words, when the task itself does not say it. At most \(TaskDelegationRecord.maxRequestLength) characters."
          ),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )

  static let returnTaskTool = Tool(
    name: "return_task",
    title: "Hand Task Back",
    description:
      "Hand a task the user gave you back to them after you worked on it. Put in result what you did and what the user still has to decide or do; it replaces the task's AI notes, as set_task_ai_notes does. With no result, or an empty one, the AI notes stay as they are. "
      + "It does not complete the task: the user confirms the work and completes the task. Do not complete a task the user handed you unless the task says you may. "
      + "It fails when the task was not handed to you. On a task you already handed back, a different result replaces the AI notes again, and repeating it with the same result changes nothing. Returns the full updated task object, whose delegation state is returned.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "id": .object([
          "type": .string("string"),
          "description": .string("Task id"),
        ]),
        "result": .object([
          "type": .string("string"),
          "description": .string(
            "What you did and what the user still has to decide or do, in Markdown (headings, lists, bold, checkboxes). Replaces the task's AI notes; omit it or pass an empty string to leave them as they are."
          ),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )

  static let clearTaskDelegationTool = Tool(
    name: "clear_task_delegation",
    title: "Take Task Back from Assistant",
    description:
      "Take a task back from you, the user's assistant, with no result: the user changed their mind, the hand-off was a mistake, or the user has read what you handed back and keeps the task as their own. "
      + "It removes the hand-off and the user's request, whether you still hold the task or already handed it back, and leaves the task and its AI notes as they are. A task that was not handed over is returned unchanged. Returns the full updated task object, whose delegation is null.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "id": .object([
          "type": .string("string"),
          "description": .string("Task id"),
        ]),
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
      ]),
      "required": .array([.string("id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: false
    )
  )
}
