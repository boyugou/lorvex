import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

/// The facts line under Today's date names the day's estimated work once: on a
/// page whose overbooked well states that estimate in its own title, the line
/// leaves it out.
@Suite("Mobile Today facts line")
struct MobileTodayFactsLineTests {
  private let busyDay = LorvexCalmToday.Facts.day(tasks: 25, workMinutes: 1_065, meetings: 5)

  @Test("a day names its tasks, estimated work, and events")
  func namesTheWork() {
    let parts = MobileTodayCalmCopy.facts(busyDay)

    #expect(parts.count == 3)
    #expect(parts.first == "25 tasks left")
    #expect(parts[1].hasSuffix("of work"))
    #expect(parts.last == "5 events")
  }

  @Test("a page that states the work elsewhere leaves it out of the line")
  func leavesOutStatedWork() {
    #expect(MobileTodayCalmCopy.facts(busyDay, workIsStated: true) == ["25 tasks left", "5 events"])
  }

  @Test("a day without an estimate reads the same whether or not the work is stated")
  func unsizedDay() {
    let unsized = LorvexCalmToday.Facts.day(tasks: 2, workMinutes: nil, meetings: 0)

    #expect(MobileTodayCalmCopy.facts(unsized, workIsStated: true) == MobileTodayCalmCopy.facts(unsized))
  }

  @Test("an empty or finished day is one sentence either way")
  func quietDays() {
    for facts in [LorvexCalmToday.Facts.empty, .allDone(done: 3)] {
      #expect(MobileTodayCalmCopy.facts(facts, workIsStated: true) == MobileTodayCalmCopy.facts(facts))
      #expect(MobileTodayCalmCopy.facts(facts).count == 1)
    }
  }
}
