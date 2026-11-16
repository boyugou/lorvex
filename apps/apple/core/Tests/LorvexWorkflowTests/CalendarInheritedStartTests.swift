import LorvexDomain
import XCTest

@testable import LorvexWorkflow

final class CalendarInheritedStartTests: XCTestCase {
  func testMaterializingAnExistingGapKeepsOnlyThatExactStart() throws {
    let input = CalendarCreateInput(
      title: "Daily meeting", timezone: "America/New_York", startDate: "2026-03-08",
      startTime: "02:30", endTime: "03:30", allDay: false)
    let inherited = CalendarInheritedStart(
      date: "2026-03-08", time: "02:30", timezone: "America/New_York", allDay: false)
    XCTAssertThrowsError(try CalendarNormalization.normalizeCalendarCreate(input))
    let preserved = try CalendarNormalization.normalizeCalendarCreate(input, inheritedStart: inherited)
    XCTAssertEqual(preserved.startTime, "02:30")
    XCTAssertEqual(preserved.dstGuard, .ok)

    for mismatched in [
      CalendarInheritedStart(date: "2026-03-07", time: "02:30", timezone: "America/New_York", allDay: false),
      CalendarInheritedStart(date: "2026-03-08", time: "02:00", timezone: "America/New_York", allDay: false),
      CalendarInheritedStart(date: "2026-03-08", time: "02:30", timezone: "America/Chicago", allDay: false),
      CalendarInheritedStart(date: "2026-03-08", time: "02:30", timezone: "America/New_York", allDay: true)
    ] {
      XCTAssertThrowsError(try CalendarNormalization.normalizeCalendarCreate(input, inheritedStart: mismatched))
    }
  }

  func testAnExistingGapRowAcceptsDetailsAndEndEditsButRejectsANewGap() throws {
    let existing = CalendarUpdateExisting(
      startDate: "2026-03-08", startTime: "02:30", endDate: nil, endTime: "03:30",
      allDay: false, timezone: "America/New_York")
    let detail = try CalendarNormalization.normalizeCalendarUpdate(
      CalendarUpdateInput(title: "Renamed", description: .set("New notes")), existing: existing)
    XCTAssertEqual(detail.effective.startTime, "02:30")
    let end = try CalendarNormalization.normalizeCalendarUpdate(
      CalendarUpdateInput(endTime: .set("04:00")), existing: existing)
    XCTAssertEqual(end.effective.startTime, "02:30")
    XCTAssertEqual(end.effective.endTime, "04:00")
    XCTAssertThrowsError(try CalendarNormalization.normalizeCalendarUpdate(
      CalendarUpdateInput(startTime: .set("02:45")), existing: existing))
    XCTAssertThrowsError(try CalendarNormalization.normalizeCalendarUpdate(
      CalendarUpdateInput(timezone: .set("America/Chicago")), existing: existing))
  }
}
