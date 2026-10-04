import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// The facts line under the Mac Today column's date names the day's estimated
/// work once: when the overbooked well states that estimate in its own title,
/// the line leaves it out. The menu bar's one-sentence summary never reads the
/// estimate, so it is unaffected.
@Suite("Today facts line")
struct TodayFactsLineTests {
  private let busyDay = LorvexCalmToday.Facts.day(tasks: 25, workMinutes: 1_065, meetings: 5)

  @Test("a day names its tasks, estimated work, and events")
  func namesTheWork() {
    let parts = TodayCalmCopy.facts(busyDay)

    #expect(parts.count == 3)
    #expect(parts.first == "25 tasks left")
    #expect(parts[1].hasSuffix("of work"))
    #expect(parts.last == "5 events")
  }

  @Test("a page that states the work elsewhere leaves it out of the line")
  func leavesOutStatedWork() {
    #expect(TodayCalmCopy.facts(busyDay, workIsStated: true) == ["25 tasks left", "5 events"])
  }

  @Test("an empty or finished day is one sentence either way")
  func quietDays() {
    for facts in [LorvexCalmToday.Facts.empty, .allDone(done: 3)] {
      #expect(TodayCalmCopy.facts(facts, workIsStated: true) == TodayCalmCopy.facts(facts))
      #expect(TodayCalmCopy.facts(facts).count == 1)
    }
  }
}
