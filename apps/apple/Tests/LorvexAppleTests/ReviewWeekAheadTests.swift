import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// The week review's look ahead reads the seven days after today and keeps
/// only the days with something on them.
@MainActor
@Test
func weekAheadListsTheNextSevenDaysThatHaveSomethingOnThem() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  for (title, offset) in [("Week ahead inside", 3), ("Week ahead last day", 7), ("Week ahead too far", 9)] {
    _ = try await store.core.createTask(
      TaskCreateDraft(title: title, plannedDate: try store.storageDate(daysFromLogicalToday: offset)))
  }

  let days = try #require(await store.loadWeekAheadAgenda())

  let today = store.logicalTodayDateString
  let keys = days.map(\.key)
  #expect(keys == keys.sorted())
  #expect(keys.allSatisfy { $0 > today })
  #expect(keys.allSatisfy { $0 <= LorvexDateFormatters.ymdUTCAddingDays(today, days: 7) ?? "" })
  #expect(days.allSatisfy { !$0.events.isEmpty || !$0.tasks.isEmpty })
  let titles = days.flatMap(\.tasks).map(\.title)
  #expect(titles.contains("Week ahead inside"))
  #expect(titles.contains("Week ahead last day"))
  #expect(!titles.contains("Week ahead too far"))
}
