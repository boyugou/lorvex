import Foundation
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Ports `calendar_timeline/temporal/tests.rs`.
///
/// The Rust suite exercises the private `resolve_local_datetime` directly
/// (chrono offset assertions); the Swift DST oracle (`DstResolution`) has its
/// own parity suite in the domain layer. Here the load-bearing case —
/// per-occurrence wall-clock preservation across a DST boundary — is ported
/// through `projectItemToAnchor`, the public projection seam.
final class CalendarTimelineTemporalTests: XCTestCase {

  private func ymd(_ s: String) -> LorvexDate { try! LorvexDate.parse(s).get() }
  private func hm(_ s: String) -> TimeOfDay { try! TimeOfDay.parse(s).get() }

  private func makeNycStandup(_ start: String, _ end: String) -> CalendarTimelineItem {
    guard case let .success(item) = CalendarTimelineItem.make(
      source: .canonical, editable: false, id: "evt-1", title: "NYC 9 AM standup",
      startDate: ymd(start), startTime: hm("09:00"), endDate: ymd(end), endTime: hm("09:30"),
      allDay: false, location: nil, color: nil, eventType: "meeting", personName: nil,
      timezone: nil, providerKind: nil, providerScope: nil, isRecurring: true,
      sourceTimeKind: "tzid", sourceTzid: "America/New_York", url: nil, attendeesJson: nil)
    else { fatalError("fixture") }
    return item
  }

  func testProjectItemPerOccurrencePreservesWallClockAcrossDst() throws {
    // 2025 US spring-forward is 2025-03-09. Mar 2 is EST (-05:00), Mar 16 is
    // EDT (-04:00). A per-occurrence projection must keep 09:00 NYC across the
    // boundary rather than drifting by the anchor's offset.
    let cases = [
      ("pre-DST", makeNycStandup("2025-03-02", "2025-03-02")),
      ("on DST day", makeNycStandup("2025-03-09", "2025-03-09")),
      ("post-DST", makeNycStandup("2025-03-16", "2025-03-16")),
    ]
    for (label, instance) in cases {
      let projected = try CalendarTimeline.projectItemToAnchor(instance, "America/New_York")
      XCTAssertEqual(
        projected.startTime, hm("09:00"), "\(label): wall-clock 09:00 NYC must survive DST")
      XCTAssertEqual(
        projected.endTime, hm("09:30"), "\(label): wall-clock 09:30 NYC must survive DST")
    }
  }

  /// A floating (no timezone, no source kind) timed event is returned
  /// unchanged regardless of the anchor zone.
  func testFloatingItemReturnedUnchanged() throws {
    guard case let .success(item) = CalendarTimelineItem.make(
      source: .canonical, editable: true, id: "f1", title: "Floating",
      startDate: ymd("2025-06-15"), startTime: hm("14:30"), endDate: ymd("2025-06-15"),
      endTime: hm("15:00"), allDay: false, location: nil, color: nil, eventType: "event",
      personName: nil, timezone: nil, providerKind: nil, providerScope: nil,
      isRecurring: false, sourceTimeKind: nil, sourceTzid: nil, url: nil, attendeesJson: nil)
    else { return XCTFail("fixture") }
    let projected = try CalendarTimeline.projectItemToAnchor(item, "America/New_York")
    XCTAssertEqual(projected.startTime, hm("14:30"))
    XCTAssertEqual(projected.startDate, ymd("2025-06-15"))
  }

  /// A UTC-kind event projects into the anchor zone by the zone's offset.
  /// 14:00Z on 2025-06-15 is 10:00 EDT in New York.
  func testUtcItemProjectsToAnchorOffset() throws {
    guard case let .success(item) = CalendarTimelineItem.make(
      source: .provider, editable: false, id: "u1", title: "UTC meeting",
      startDate: ymd("2025-06-15"), startTime: hm("14:00"), endDate: ymd("2025-06-15"),
      endTime: hm("15:00"), allDay: false, location: nil, color: nil, eventType: "event",
      personName: nil, timezone: nil, providerKind: "eventkit", providerScope: "s",
      isRecurring: false, sourceTimeKind: "utc", sourceTzid: nil, url: nil, attendeesJson: nil)
    else { return XCTFail("fixture") }
    let projected = try CalendarTimeline.projectItemToAnchor(item, "America/New_York")
    XCTAssertEqual(projected.startTime, hm("10:00"))
    XCTAssertEqual(projected.endTime, hm("11:00"))
    XCTAssertEqual(projected.startDate, ymd("2025-06-15"))
  }
}
