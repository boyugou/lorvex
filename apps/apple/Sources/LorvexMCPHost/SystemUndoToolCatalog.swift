import MCP

extension SystemContextToolCatalog {
  static let undoAIChangeTool = Tool(
    name: "undo_ai_change",
    title: "Undo AI Change",
    description:
      "Undo an update you made to a task or to a one-off calendar event, using its entry in "
      + "get_ai_changelog (an entry marked undoable). Each field that change moved goes back to "
      + "its earlier value, but only where the field still holds what the change set: a field "
      + "edited since, by the user or another assistant, is left alone and listed under kept. "
      + "The restore is an ordinary, logged, synced update. An event's date, times, all_day, and "
      + "timezone count as one field, schedule. Only an update that an assistant made, with a "
      + "recorded before-and-after, can be undone, and not one to an event that repeats or "
      + "belongs to a series; a change the user made cannot. Use it when the user says to take "
      + "back something you changed. Returns {entity_type, task or event, reverted, kept}; "
      + "reverted is empty when the item already differs from that change everywhere.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        IdempotencyKeySchema.propertyName: IdempotencyKeySchema.property,
        "changelog_id": .object([
          "type": .string("string"),
          "description": .string("The id of the change, from get_ai_changelog."),
        ]),
      ]),
      "required": .array([.string("changelog_id")]),
    ]),
    annotations: .init(
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    )
  )
}
