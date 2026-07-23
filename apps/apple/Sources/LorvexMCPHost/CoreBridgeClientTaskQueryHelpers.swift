import LorvexCore
import MCP

extension CoreBridgeClient {
  static func pagedTasksValue(
    from page: TaskPageResult,
    options: TaskValueOptions = .full,
    extra: [String: Value] = [:]
  ) -> Value {
    var value = MCPPagination.merged(
      into: ["tasks": taskValues(from: page.tasks, options: options)],
      totalMatching: page.totalMatching, returned: page.returned, limit: page.limit,
      offset: page.offset, nextOffset: page.nextOffset, truncated: page.truncated)
    extra.forEach { value[$0.key] = $0.value }
    return .object(value)
  }

  static func searchTasksValue(
    from result: TaskSearchResult,
    options: TaskValueOptions = .full
  ) -> Value {
    MCPPagination.object(
      domain: [
        "tasks": taskValuesWithMatchReasons(
          from: result.tasks, query: result.query, options: options),
        "query": .string(result.query),
      ],
      totalMatching: result.totalMatching, returned: result.returned, limit: result.limit,
      offset: result.offset, nextOffset: result.nextOffset, truncated: result.truncated)
  }

  static func taskValuesWithMatchReasons(
    from tasks: [LorvexTask],
    query: String,
    options: TaskValueOptions = .full
  ) -> Value {
    .array(tasks.map { task in
      var object = taskValue(from: task, options: options).objectValue ?? [:]
      object["match_reasons"] = .array(matchReasons(task: task, query: query).map(Value.string))
      return .object(object)
    })
  }

  static func matchReasons(task: LorvexTask, query: String) -> [String] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    var reasons: [String] = []
    if task.title.localizedCaseInsensitiveContains(trimmed) { reasons.append("title") }
    if task.notes.localizedCaseInsensitiveContains(trimmed) { reasons.append("notes") }
    if task.aiNotes?.localizedCaseInsensitiveContains(trimmed) == true { reasons.append("ai_notes") }
    if task.tags.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) }) {
      reasons.append("tags")
    }
    return reasons
  }
}
