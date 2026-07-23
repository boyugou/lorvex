import MCP

extension ToolRegistry {
  func overviewResult(arguments: [String: Value] = [:]) async throws -> CallTool.Result {
    let shape = try StrictScalarArguments.string(
      arguments["shape"], field: "shape", default: "compact")
    if shape != "full" {
      // Rule 6 fencing (top-task titles) is applied centrally by the dispatch
      // layer for every tool result; this handler just shapes the payload.
      let structured = try await overviewCompactPayload()
      return fencedReadResult(text: "Loaded Lorvex compact overview.", value: structured)
    }

    let snapshot = try await coreBridge.loadOverview()
    var structuredObject: [String: Value] = [
      "focus_title": .string("Today"),
      "local_change_seq": .int(snapshot.localChangeSequence),
      "tasks": .array(snapshot.tasks),
    ]
    if let currentFocus = snapshot.currentFocus {
      structuredObject["current_focus"] = currentFocus
    }
    // Rule 6 fencing (task titles/notes inside `tasks`) is applied centrally
    // by the dispatch layer for every tool result.
    let structured = Value.object(structuredObject)
    return CallTool.Result(
      content: [
        .text(
          text: "Lorvex has \(snapshot.tasks.count) open task(s).", annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(structured),
      isError: false
    )
  }
}
