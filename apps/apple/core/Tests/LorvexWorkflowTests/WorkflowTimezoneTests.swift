import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Parity port of `lorvex_workflow::timezone` tests.
final class WorkflowTimezoneTests: XCTestCase {
  private func insertTzPreference(_ writer: any DatabaseWriter, jsonValue: String) throws {
    try writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO preferences (key, value, version, updated_at) "
          + "VALUES ('timezone', ?1, "
          + "        '0000000000000_0000_0000000000000000', '2026-03-08T01:00:00Z')",
        arguments: [jsonValue])
    }
  }

  private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int)
    -> Date
  {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    cal.locale = Locale(identifier: "en_US_POSIX")
    var dc = DateComponents()
    dc.year = year
    dc.month = month
    dc.day = day
    dc.hour = hour
    dc.minute = minute
    dc.second = second
    return cal.date(from: dc)!
  }

  func testActiveTimezoneNameReadsJsonStringPreference() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTzPreference(store.writer, jsonValue: "\"America/Los_Angeles\"")
    let name = try store.writer.read { db in
      try WorkflowTimezone.activeTimezoneName(db)
    }
    XCTAssertEqual(name, "America/Los_Angeles")
  }

  func testActiveTimezoneNameReturnsNilWhenNoPreference() throws {
    let store = try WorkflowTestSupport.freshStore()
    let name = try store.writer.read { db in
      try WorkflowTimezone.activeTimezoneName(db)
    }
    XCTAssertNil(name)
  }

  func testActiveTimezoneNameRejectsNonJsonRawValue() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTzPreference(store.writer, jsonValue: "America/Los_Angeles")
    XCTAssertThrowsError(
      try store.writer.read { db in
        _ = try WorkflowTimezone.activeTimezoneName(db)
      }
    ) { error in
      XCTAssertTrue("\(error)".contains("timezone"))
    }
  }

  func testActiveTimezoneNameRejectsInvalidJsonTimezoneString() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTzPreference(store.writer, jsonValue: "\"Not/AZone\"")
    XCTAssertThrowsError(
      try store.writer.read { db in
        _ = try WorkflowTimezone.activeTimezoneName(db)
      }
    ) { error in
      XCTAssertTrue("\(error)".contains("timezone"))
    }
  }

  func testTodayYmdUsesTimezonePreferenceCalendarDay() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTzPreference(store.writer, jsonValue: "\"America/Los_Angeles\"")
    let now = utc(2026, 3, 8, 1, 0, 0)
    let ymd = try store.writer.read { db in
      try WorkflowTimezone.todayYmdForConn(db, now: now)
    }
    XCTAssertEqual(ymd, "2026-03-07")
  }

  func testTrailingDayWindowUsesTimezoneMidnightBoundaries() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTzPreference(store.writer, jsonValue: "\"America/Los_Angeles\"")
    let now = utc(2026, 3, 15, 12, 0, 0)
    let bounds = try store.writer.read { db in
      try WorkflowTimezone.trailingDayWindowUtcBoundsForConn(db, now: now, spanDays: 7)
    }
    XCTAssertEqual(bounds.fromDay, "2026-03-09")
    XCTAssertEqual(bounds.toDay, "2026-03-15")
    XCTAssertEqual(bounds.startUtc, "2026-03-09T07:00:00.000Z")
    XCTAssertEqual(bounds.endUtc, "2026-03-16T07:00:00.000Z")
  }

  /// Regression guard: `firstValidUtcForLocalDay` is correct as written — it
  /// extracts the probe day from `probeUtc` in **UTC**. An audit proposed
  /// switching the probe calendar to `zone`; that would read midnight-UTC as
  /// the previous local day for every west-of-UTC zone, introducing an
  /// off-by-one. These cases lock in the current behavior so the "fix" is not
  /// reintroduced.
  func testFirstValidUtcForLocalDayResolvesSkippedAndNormalDays() throws {
    // Pacific/Apia skipped all of 2011-12-30 when it crossed the dateline
    // (29 Dec 23:59:59 -10:00 jumped straight to 31 Dec 00:00:00 +14:00). The
    // skipped day must fall forward to 31 Dec 00:00 local = 2011-12-30T10:00Z.
    let apia = try XCTUnwrap(TimeZone(identifier: "Pacific/Apia"))
    let skipped = try XCTUnwrap(
      WorkflowTimezone.firstValidUtcForLocalDay(
        day: IsoDate.YMD(year: 2011, month: 12, day: 30), zone: apia))
    XCTAssertEqual(skipped, utc(2011, 12, 30, 10, 0, 0))

    // A normal (non-skipped) west-of-UTC day resolves to its own local
    // midnight: 2026-03-15 00:00 PDT (-7) = 2026-03-15T07:00:00Z. The audit's
    // proposed `probeCal.timeZone = zone` change would wrongly return
    // 2026-03-14T07:00:00Z here.
    let la = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let normal = try XCTUnwrap(
      WorkflowTimezone.firstValidUtcForLocalDay(
        day: IsoDate.YMD(year: 2026, month: 3, day: 15), zone: la))
    XCTAssertEqual(normal, utc(2026, 3, 15, 7, 0, 0))
  }
}
