import Foundation
import LorvexCore
import Testing

/// The product day's clock: minutes since midnight in the product zone, and
/// only while that zone's date is the product day.
struct LorvexProductDayClockTests {
  private static let shanghai = TimeZone(identifier: "Asia/Shanghai")!
  private static let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
  /// 01:30 on 2026-10-02 in Shanghai, and 10:30 on 2026-10-01 in Los Angeles.
  private static let instant = ISO8601DateFormatter().date(from: "2026-10-01T17:30:00Z")!

  @Test("The minutes come from the product zone while its date is the product day")
  func minutesInTheProductZone() {
    #expect(
      LorvexProductDayClock.nowMinutes(on: "2026-10-02", in: Self.shanghai, at: Self.instant) == 90)
    #expect(
      LorvexProductDayClock.nowMinutes(on: "2026-10-01", in: Self.losAngeles, at: Self.instant)
        == 630)
  }

  @Test("A product day the zone's clock is not on has no clock position")
  func anotherDayHasNoClockPosition() {
    #expect(
      LorvexProductDayClock.nowMinutes(on: "2026-10-01", in: Self.shanghai, at: Self.instant) == nil)
    #expect(
      LorvexProductDayClock.nowMinutes(on: "2026-10-02", in: Self.losAngeles, at: Self.instant)
        == nil)
  }
}
