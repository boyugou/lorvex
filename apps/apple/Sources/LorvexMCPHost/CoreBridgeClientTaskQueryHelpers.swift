import LorvexCore
import LorvexDomain
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

  /// The fields of `task` that account for a search hit on `query`, compared
  /// the way the store's search compares text (case, accents, and letter
  /// variants such as ё, ł, and ß ignored, via `SearchFold`). A field is named
  /// when it holds every word of the query; when the words are spread over
  /// several fields, each field holding at least one of them is named, so a
  /// task the search found always names where it was found.
  static func matchReasons(task: LorvexTask, query: String) -> [String] {
    let words = SearchFold.tokens(query)
    guard !words.isEmpty else { return [] }
    let fields: [(name: String, text: String)] = [
      ("title", SearchFold.fold(task.title)),
      ("notes", SearchFold.fold(task.notes)),
      ("ai_notes", SearchFold.fold(task.aiNotes ?? "")),
      ("tags", task.tags.map(SearchFold.fold).joined(separator: " ")),
    ]
    let holdingEveryWord = fields.filter { field in words.allSatisfy { field.text.contains($0) } }
    let named =
      holdingEveryWord.isEmpty
      ? fields.filter { field in words.contains { field.text.contains($0) } }
      : holdingEveryWord
    return named.map(\.name)
  }
}
