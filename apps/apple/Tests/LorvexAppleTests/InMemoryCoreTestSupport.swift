import Foundation
import LorvexCore
import LorvexDomain

/// A real `SwiftLorvexCoreService` over an empty in-memory GRDB store running
/// the canonical schema. The default core for app-layer tests: production
/// query/write semantics with no on-disk footprint and no cross-test state.
/// Its wall clock reads 08:00 today in the system timezone, the zone an empty
/// store anchors to.
func makeInMemoryCore() throws -> SwiftLorvexCoreService {
  try SwiftLorvexCoreService.inMemory(wallClock: morningWallClock(in: .current))
}

/// A real in-memory core pre-populated with the fixed preview dataset
/// (`LorvexPreviewCoreFactory.makeSeeded`): the lists/tasks/habits/calendar/
/// memory/review fixture tests reference through `LorvexPreviewSeedID`.
/// Its wall clock is `wallClock`, by default ``seedMorningWallClock()``; a test
/// that derives expected dates from "now" passes the clock it reads, so the
/// core and the expectation agree whatever time of day the suite runs.
func makeSeededInMemoryCore(
  wallClock: @escaping @Sendable () -> Date = seedMorningWallClock()
) async throws -> SwiftLorvexCoreService {
  try await LorvexPreviewCoreFactory.makeSeeded(wallClock: wallClock)
}

/// A wall clock fixed at 08:00 today in the seed's timezone
/// (America/Los_Angeles).
func seedMorningWallClock() -> @Sendable () -> Date {
  morningWallClock(in: TimeZone(identifier: "America/Los_Angeles") ?? .current)
}

/// A wall clock fixed at 08:00 on today's date in `zone`: before any seeded
/// working hours begin, so a schedule proposed for today packs from the
/// working-hours start whatever time of day the suite runs.
func morningWallClock(in zone: TimeZone) -> @Sendable () -> Date {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = zone
  let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
  return { morning }
}

/// Plan `taskID` for the `yyyy-MM-dd` day `date`, giving it `time` (minutes
/// since midnight) on that day when one is passed. Returns the updated task.
@discardableResult
func planTask(
  _ core: any LorvexCoreServicing, _ taskID: LorvexTask.ID, on date: String,
  time: Range<Int>? = nil
) async throws -> LorvexTask {
  guard let day = LorvexDateFormatters.ymdUTC.date(from: date) else {
    throw CocoaError(.formatting)
  }
  return try await core.updateTask(
    TaskUpdateDraft(id: taskID, plannedDate: .set(day), plannedTime: time.map { .set($0) } ?? .unset))
}
