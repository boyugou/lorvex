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
    // Rule 6 fencing (task titles/notes, the briefing) is applied centrally by
    // the dispatch layer for every tool result.
    let structured = Value.object([
      "date": .string(snapshot.date),
      "local_change_seq": .int(snapshot.localChangeSequence),
      "briefing": snapshot.briefing.map(Value.string) ?? .null,
      "today": .array(snapshot.today),
      "tasks": .array(snapshot.tasks),
    ])
    return CallTool.Result(
      content: [
        .text(
          text: "Today holds \(snapshot.today.count) task(s).", annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(structured),
      isError: false
    )
  }
}
