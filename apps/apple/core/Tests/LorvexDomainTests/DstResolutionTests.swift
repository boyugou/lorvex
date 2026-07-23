import Foundation
import XCTest

@testable import LorvexDomain

/// DST gap/overlap contract tests. The asserted UTC instants are the canonical
/// expected outputs reproduced with Foundation's `Calendar`/`TimeZone`.
final class DstResolutionTests: XCTestCase {
  private func ny() -> TimeZone { TimeZone(identifier: "America/New_York")! }

  private func naive(
    _ date: (Int, Int, Int), _ time: (Int, Int, Int)
  ) -> NaiveDateTime {
    NaiveDateTime(
      year: date.0, month: date.1, day: date.2,
      hour: time.0, minute: time.1, second: time.2)
  }

  private func utcString(_ d: Date) -> String {
    SyncTimestampFormat.utcCalendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: d
    ).formattedZ
  }

  func testResolveValidForNormalTime() {
    let input = naive((2026, 4, 18), (9, 0, 0))
    let result = DstResolution.resolveLocalDatetime(timezone: ny(), local: input)
    guard case let .valid(dt) = result else { return XCTFail("expected valid, got \(result)") }
    // EDT offset in April = UTC-4 → 09:00 local = 13:00 UTC.
    XCTAssertEqual(utcString(dt), "2026-04-18T13:00:00Z")
  }

  func testResolveAmbiguousForFallBack() {
    // 2026-11-01 01:30 New_York: 01:30 EDT (UTC-4) then again 01:30 EST (UTC-5).
    let input = naive((2026, 11, 1), (1, 30, 0))
    let result = DstResolution.resolveLocalDatetime(timezone: ny(), local: input)
    guard case let .ambiguous(earlier, later) = result else {
      return XCTFail("expected ambiguous, got \(result)")
    }
    XCTAssertEqual(utcString(earlier), "2026-11-01T05:30:00Z")
    XCTAssertEqual(utcString(later), "2026-11-01T06:30:00Z")
  }

  func testResolveSkippedForSpringForwardGap() {
    // 2026-03-08 02:30 New_York falls in the spring-forward gap (02:00 EST →
    // 03:00 EDT). Snapping 15m at a time lands at 03:00 EDT = 07:00 UTC.
    let input = naive((2026, 3, 8), (2, 30, 0))
    let result = DstResolution.resolveLocalDatetime(timezone: ny(), local: input)
    guard case let .skipped(requested, snappedTo) = result else {
      return XCTFail("expected skipped, got \(result)")
    }
    XCTAssertEqual(requested, input)
    XCTAssertEqual(utcString(snappedTo), "2026-03-08T07:00:00Z")
  }
}

extension DateComponents {
  /// Render the components as `YYYY-MM-DDTHH:MM:SSZ` for the DST parity asserts.
  fileprivate var formattedZ: String {
    String(
      format: "%04d-%02d-%02dT%02d:%02d:%02dZ",
      year ?? 0, month ?? 0, day ?? 0, hour ?? 0, minute ?? 0, second ?? 0)
  }
}
