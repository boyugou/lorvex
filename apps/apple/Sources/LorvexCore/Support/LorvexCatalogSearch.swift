import Foundation

/// The one catalog-search projection every read surface shares, so a query
/// returns the same lists / habits / memory entries on macOS and on
/// iOS/iPadOS. Pure and synchronous: it filters already-loaded
/// in-memory pools and never touches the store.
///
/// **Field set** is the union of what any surface historically searched — a
/// superset is safe because a wider haystack only ever surfaces *more* of what
/// the user could plausibly mean, never fewer:
/// - lists: name (shown and stored, ``LorvexList/matchNames``), description,
///   AI notes, icon, color
/// - habits: name, cue, frequency type, icon, color
/// - memory: key, content
///
/// **Match semantics** is whitespace-split term-AND (``matches(_:fields:)``):
/// every term must appear in some field, in any order. This is strictly more
/// flexible than a single whole-query substring — "gym morning" finds a
/// "Morning gym" habit that a contiguous-substring match would miss — while
/// still collapsing to plain substring behavior for a single-word query. An
/// empty or all-whitespace query matches everything.
///
/// **Comparison** ignores case and accents and follows the user's language
/// (`localizedStandardContains`), so "cafe" finds "Café" and "manana" finds
/// "Mañana", as the store's full-text index does for tasks.
public enum LorvexCatalogSearch {
  /// Whether every whitespace-separated term in `query` is a substring of at
  /// least one non-nil entry in `fields`, ignoring case and accents. An empty
  /// (or all-whitespace) query matches everything.
  public static func matches(_ query: String, fields: [String?]) -> Bool {
    let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !terms.isEmpty else { return true }
    let searchable = fields.compactMap { $0 }
    return terms.allSatisfy { term in
      searchable.contains { $0.localizedStandardContains(term) }
    }
  }

  public static func lists(_ lists: [LorvexList], query: String) -> [LorvexList] {
    filter(lists, query: query) { list in
      list.matchNames + [list.description, list.aiNotes, list.icon, list.color]
    }
  }

  public static func habits(_ habits: [LorvexHabit], query: String) -> [LorvexHabit] {
    filter(habits, query: query) { habit in
      [habit.name, habit.cue, habit.frequencyType, habit.icon, habit.color]
    }
  }

  public static func memory(_ entries: [MemoryEntry], query: String) -> [MemoryEntry] {
    filter(entries, query: query) { entry in
      [entry.key, entry.content]
    }
  }

  private static func filter<Item>(
    _ items: [Item],
    query: String,
    fields: (Item) -> [String?]
  ) -> [Item] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return items }
    return items.filter { matches(trimmed, fields: fields($0)) }
  }
}
