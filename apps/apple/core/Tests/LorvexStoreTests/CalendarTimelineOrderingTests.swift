import Foundation
import LorvexDomain
import XCTest

@testable import LorvexStore

final class CalendarTimelineOrderingTests: XCTestCase {
  func testMixedFloatingAndRepeatedClocksHaveOneOrderForEveryInputOrder() throws {
    let floating = try event("floating", time: "01:30", timezone: nil)
    let earlier = try CalendarTimeline.projectItemToAnchor(
      event("earlier", time: "05:50"), "America/New_York")
    let later = try CalendarTimeline.projectItemToAnchor(
      event("later", time: "06:10"), "America/New_York")
    XCTAssertEqual(earlier.startTime?.asString, "01:50")
    XCTAssertEqual(later.startTime?.asString, "01:10")
    for input in permutations([earlier, later, floating]) {
      let sorted = try CalendarTimeline.sorted(input, anchorTimezone: "America/New_York")
      XCTAssertEqual(sorted.map(\.id), ["floating", "earlier", "later"])
      XCTAssertEqual(sorted.first, floating)
      XCTAssertNil(sorted.first?.projection)
    }
  }

  func testSameInstantUsesBinaryTitleThenStableIdentity() throws {
    let decomposed = try event("z", time: "05:00", title: "e\u{301}")
    let composedA = try event("a", time: "05:00", title: "é")
    let composedB = try event("b", time: "05:00", title: "é")
    for input in permutations([decomposed, composedA, composedB]) {
      let projected = try input.map {
        try CalendarTimeline.projectItemToAnchor($0, "America/New_York")
      }
      let sorted = try CalendarTimeline.sorted(projected, anchorTimezone: "America/New_York")
      XCTAssertEqual(sorted.map(\.id), ["z", "a", "b"])
    }
  }

  func testMissingTimesFollowTimedRowsAndStayCivil() throws {
    let timed = try event("timed", time: "00:00", timezone: nil)
    let firstDay = try event("first-day", time: nil, title: "A date")
    let secondDay = try event("second-day", time: nil, title: "Z day")
    let sorted = try CalendarTimeline.sorted(
      [secondDay, firstDay, timed], anchorTimezone: "Asia/Tokyo")
    XCTAssertEqual(sorted.map(\.id), ["timed", "first-day", "second-day"])
    XCTAssertEqual(sorted.map { $0.startDate.asString }, Array(repeating: "2026-11-01", count: 3))
    XCTAssertTrue(sorted.allSatisfy { $0.projection == nil })
  }

  private func event(_ id: String, time: String?, timezone: String? = "UTC", title: String? = nil)
    throws -> CalendarTimelineItem
  {
    try CalendarTimelineItem.make(
      source: .canonical, editable: true, id: id, title: title ?? id,
      startDate: LorvexDate.parse("2026-11-01").get(),
      startTime: time.map { try TimeOfDay.parse($0).get() }, endDate: nil, endTime: nil,
      allDay: time == nil, location: nil, color: nil, eventType: "event", personName: nil,
      timezone: timezone, providerKind: nil, providerScope: nil, isRecurring: false,
      sourceTimeKind: nil, sourceTzid: nil, url: nil, attendeesJson: nil
    ).get()
  }

  private func permutations(_ items: [CalendarTimelineItem]) -> [[CalendarTimelineItem]] {
    guard items.count > 1 else { return [items] }
    return items.indices.flatMap { index in
      var rest = items
      let first = rest.remove(at: index)
      return permutations(rest).map { [first] + $0 }
    }
  }
}
