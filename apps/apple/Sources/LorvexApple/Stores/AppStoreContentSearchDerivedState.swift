import Foundation
import LorvexCore

extension AppStore {
  var filteredCalendarEvents: [CalendarTimelineEvent] {
    let query = trimmedSearchText
    let events = calendarTimeline?.events ?? []
    guard !query.isEmpty else { return events }
    return events.filter { event in
      [
        event.title,
        event.location ?? "",
        event.eventType,
        event.source,
      ].contains { value in
        value.localizedCaseInsensitiveContains(query)
      }
    }
  }

  var filteredLists: [LorvexList] {
    LorvexCatalogSearch.lists(lists?.lists ?? [], query: trimmedSearchText)
  }

  /// Every list in synced `position` order, ignoring the task search text. The
  /// sidebar's Lists section is navigation — a task search must not hide lists
  /// from it — and it's the surface the list-reorder drag operates on, so the
  /// displayed order and the drag math agree on this collection. The core returns
  /// lists already ordered by `position`, so this is just the unfiltered catalog.
  var orderedLists: [LorvexList] {
    lists?.lists ?? []
  }

  var filteredHabits: [LorvexHabit] {
    LorvexCatalogSearch.habits(habits?.habits ?? [], query: trimmedSearchText)
  }

  /// Memory entries narrowed by the shared `searchText` through the shared
  /// ``LorvexCatalogSearch`` projection, so the Memory workspace filters exactly
  /// like the same surface on iOS. Preserves the core's returned order (AI and
  /// human entries alike) and is a pure client-side filter over the already
  /// loaded snapshot — it never re-queries the core.
  var filteredMemoryEntries: [MemoryEntry] {
    LorvexCatalogSearch.memory(memoryEntries, query: trimmedSearchText)
  }
}
