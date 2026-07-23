import Foundation

extension LorvexTask {
  /// Case-insensitive term-AND match of `query` against the task's title,
  /// notes, priority, status, and tags.
  ///
  /// Platform-neutral so every surface scores a task identically: the macOS
  /// workspace search filter and command palette filter in-memory pools through
  /// it, and the core keeps one definition of "what a search string matches on a
  /// task." Match semantics are the same term-AND rule catalog search uses
  /// (``LorvexCatalogSearch/matches(_:fields:)``): the query is split on
  /// whitespace and every term must be a substring of some field, in any order —
  /// so "gym morning" matches a "Morning gym" task. A single-word query collapses
  /// to plain substring behavior; an empty/all-whitespace query matches every task.
  /// Task and catalog search therefore behave identically for the user.
  public func matchesSearch(_ query: String) -> Bool {
    LorvexCatalogSearch.matches(query, fields: [
      title,
      notes,
      priority.rawValue,
      status.rawValue,
      tags.joined(separator: " "),
    ])
  }
}
