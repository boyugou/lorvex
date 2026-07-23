import Foundation
import XCTest

@testable import LorvexDomain

/// Ports `time/tests.rs`: timezone parsing/normalization, anchored-timezone
/// resolution, sync-timestamp formatting/parsing, and the `LorvexDate` /
/// `TimeOfDay` newtypes.
final class TimeTests: XCTestCase {
  /// Build a UTC instant from y/m/d h:m:s using the deterministic UTC calendar.
  private func utc(
    _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int
  ) -> Date {
    var dc = DateComponents()
    dc.year = y; dc.month = mo; dc.day = d; dc.hour = h; dc.minute = mi; dc.second = s
    return SyncTimestampFormat.utcCalendar.date(from: dc)!
  }

  func testSyncTimestampDateAccessorRoundTripsMillis() {
    let ts = SyncTimestamp.parse("2024-05-26T08:00:00.000Z")!
    XCTAssertEqual(ts.date.timeIntervalSince1970, 1_716_710_400.0)
  }

  // ── Timezone ────────────────────────────────────────────────────────

  func testParseTimezoneNameAcceptsValidIana() {
    XCTAssertEqual(Timezone.parseTimezoneName("America/Los_Angeles")?.identifier, "America/Los_Angeles")
  }

  func testNormalizeTimezoneNameRejectsBlankOrInvalid() {
    XCTAssertNil(Timezone.normalizeTimezoneName("   "))
    XCTAssertNil(Timezone.normalizeTimezoneName("Not/AZone"))
    XCTAssertEqual(
      Timezone.normalizeTimezoneName("  America/Los_Angeles  "), "America/Los_Angeles")
    XCTAssertEqual(Timezone.normalizeProductTimezoneName(" GMT "), "UTC")
    XCTAssertEqual(Timezone.normalizeProductTimezoneName("UTC"), "UTC")
    XCTAssertNil(Timezone.normalizeProductTimezoneName("PST"))
    XCTAssertNil(Timezone.normalizeProductTimezoneName("GMT+5"))
    XCTAssertNil(Timezone.normalizeProductTimezoneName("Etc/UTC"))
  }

  func testParseJsonTimezonePreferenceAcceptsCanonical() {
    XCTAssertEqual(
      Timezone.parseJsonTimezonePreference("\"America/Los_Angeles\""), "America/Los_Angeles")
  }

  func testParseJsonTimezonePreferenceRejectsNonJsonOrInvalid() {
    XCTAssertNil(Timezone.parseJsonTimezonePreference("America/Los_Angeles"))
    XCTAssertNil(Timezone.parseJsonTimezonePreference("\"Not/AZone\""))
  }

  func testParseRequiredTimezonePreferenceAcceptsCanonical() {
    guard case let .success(v) = Timezone.parseRequiredTimezonePreference(
      "\"America/Los_Angeles\"", key: "timezone")
    else { return XCTFail() }
    XCTAssertEqual(v, "America/Los_Angeles")
  }

  func testParseRequiredTimezonePreferenceRejectsNonJsonOrInvalid() {
    guard case let .failure(malformed) = Timezone.parseRequiredTimezonePreference(
      "America/Los_Angeles", key: "timezone")
    else { return XCTFail() }
    XCTAssertTrue(malformed.description.contains("canonical JSON timezone string"))

    guard case let .failure(invalid) = Timezone.parseRequiredTimezonePreference(
      "\"Not/AZone\"", key: "timezone")
    else { return XCTFail() }
    XCTAssertTrue(invalid.description.contains("unknown timezone"))
  }

  func testResolveAnchoredTimezonePrefersActive() {
    guard case let .success(v) = Timezone.resolveAnchoredTimezoneName(
      activeTimezone: "America/Los_Angeles",
      systemTimezoneLookup: .failure(TimezoneResolutionError("lookup should not be needed")))
    else { return XCTFail() }
    XCTAssertEqual(v, "America/Los_Angeles")
  }

  func testResolveAnchoredTimezoneUsesSystemWhenActiveMissing() {
    guard case let .success(v) = Timezone.resolveAnchoredTimezoneName(
      activeTimezone: nil, systemTimezoneLookup: .success("America/New_York"))
    else { return XCTFail() }
    XCTAssertEqual(v, "America/New_York")
  }

  func testResolveAnchoredTimezoneRejectsLookupFailure() {
    guard case let .failure(e) = Timezone.resolveAnchoredTimezoneName(
      activeTimezone: nil,
      systemTimezoneLookup: .failure(TimezoneResolutionError("timezone lookup failed")))
    else { return XCTFail() }
    XCTAssertTrue(e.description.contains("resolvable system IANA timezone"))
  }

  func testResolveAnchoredTimezoneRejectsInvalidSystemTimezone() {
    guard case let .failure(e) = Timezone.resolveAnchoredTimezoneName(
      activeTimezone: nil, systemTimezoneLookup: .success("Mars/Phobos"))
    else { return XCTFail() }
    XCTAssertTrue(e.description.contains("valid IANA timezone"))
  }

  func testTodayYmdUsesConfiguredTimezoneCalendarDay() {
    // 2026-03-08T01:00:00Z is 2026-03-07 17:00 in Los Angeles (PST); local day 03-07.
    let now = utc(2026, 3, 8, 1, 0, 0)
    XCTAssertEqual(
      Timezone.todayYmdForTimezoneName(
        now: now, timezoneName: "America/Los_Angeles", systemFallback: TimeZone(identifier: "UTC")!),
      "2026-03-07")
  }

  func testDatePlusDaysYmdUsesConfiguredTimezoneCalendarDay() {
    let now = utc(2026, 3, 8, 1, 0, 0)
    XCTAssertEqual(
      Timezone.datePlusDaysYmdForTimezoneName(
        now: now, timezoneName: "America/Los_Angeles", offsetDays: 1,
        systemFallback: TimeZone(identifier: "UTC")!),
      "2026-03-08")
  }

  func testNextMidnightUsesConfiguredZoneAcrossDst() throws {
    // 03:00 PDT on spring-forward day. The next product midnight is 21 wall
    // hours later at 07:00Z, independent of the host process timezone.
    let now = utc(2026, 3, 8, 10, 0, 0)
    let midnight = try XCTUnwrap(
      Timezone.nextMidnight(after: now, timezoneName: "America/Los_Angeles"))
    XCTAssertEqual(midnight, utc(2026, 3, 9, 7, 0, 0))
    XCTAssertNil(Timezone.nextMidnight(after: now, timezoneName: "Mars/Olympus_Mons"))
  }

  /// `nil` preference uses the supplied system fallback zone, never panics. Ports
  /// `today_ymd_for_timezone_name_uses_local_when_preference_is_none` with the
  /// fallback made explicit (the domain layer takes no implicit host-clock read).
  func testTodayYmdUsesFallbackWhenPreferenceNil() {
    let now = utc(2026, 3, 8, 1, 0, 0)
    let fallback = TimeZone(identifier: "America/New_York")!
    var cal = Calendar(identifier: .gregorian)
    cal.locale = Locale(identifier: "en_US_POSIX")
    cal.timeZone = fallback
    let c = cal.dateComponents([.year, .month, .day], from: now)
    let expected = IsoDate.YMD(year: c.year!, month: c.month!, day: c.day!).canonicalString
    XCTAssertEqual(
      Timezone.todayYmdForTimezoneName(now: now, timezoneName: nil, systemFallback: fallback),
      expected)
  }

  /// An invalid (corrupt) preference falls back to the system zone in release
  /// builds. Ports `today_ymd_..._falls_back_to_local_for_invalid_timezone_in_release`;
  /// the dev-build `debug_assert!` panic variant is intentionally not ported (a
  /// Swift trap is not catchable by XCTest).
  func testTodayYmdFallsBackForInvalidTimezone() {
    let now = utc(2026, 3, 8, 1, 0, 0)
    let fallback = TimeZone(identifier: "UTC")!
    XCTAssertEqual(
      Timezone.todayYmdForTimezoneName(now: now, timezoneName: "Not/AZone", systemFallback: fallback),
      "2026-03-08")
  }

  // ── Sync timestamp ───────────────────────────────────────────────────

  func testSyncTimestampNowHasMillisecondPrecision() {
    let s = SyncTimestampFormat.syncTimestampNow()
    XCTAssertEqual(s.count, 24)
    XCTAssertTrue(s.hasSuffix("Z"))
    let dot = s.firstIndex(of: ".")!
    let frac = s[s.index(after: dot)..<s.index(before: s.endIndex)]
    XCTAssertEqual(frac.count, 3)
  }

  func testSyncTimestampNowIsLexComparableAcross1000Samples() {
    var last: String?
    for _ in 0..<1000 {
      let s = SyncTimestampFormat.syncTimestampNow()
      XCTAssertEqual(s.count, 24)
      if let prev = last { XCTAssertLessThanOrEqual(prev, s) }
      last = s
    }
  }

  func testNormalizeSyncTimestampAcceptsMicrosecondInput() {
    XCTAssertEqual(
      SyncTimestampFormat.normalizeSyncTimestamp("2026-03-20T15:30:00.123456Z"),
      "2026-03-20T15:30:00.123Z")
  }

  func testNormalizeSyncTimestampIdempotentOnMillis() {
    XCTAssertEqual(
      SyncTimestampFormat.normalizeSyncTimestamp("2026-03-20T15:30:00.123Z"),
      "2026-03-20T15:30:00.123Z")
  }

  func testNormalizeSyncTimestampPadsSecondPrecision() {
    XCTAssertEqual(
      SyncTimestampFormat.normalizeSyncTimestamp("2026-03-20T15:30:00Z"),
      "2026-03-20T15:30:00.000Z")
  }

  func testNormalizeSyncTimestampRejectsMalformed() {
    XCTAssertNil(SyncTimestampFormat.normalizeSyncTimestamp("not-a-timestamp"))
    XCTAssertNil(SyncTimestampFormat.normalizeSyncTimestamp(""))
  }

  func testNormalizeSyncTimestampRejectsNonUtcOffsets() {
    XCTAssertNil(SyncTimestampFormat.normalizeSyncTimestamp("2026-03-20T15:30:00.123+05:30"))
    XCTAssertNil(SyncTimestampFormat.normalizeSyncTimestamp("2026-03-20T15:30:00.123-08:00"))
    XCTAssertNil(SyncTimestampFormat.normalizeSyncTimestamp("2026-03-20T15:30:00.123+00:01"))
  }

  func testNormalizeSyncTimestampAcceptsExplicitZeroOffset() {
    XCTAssertEqual(
      SyncTimestampFormat.normalizeSyncTimestamp("2026-03-20T15:30:00.123+00:00"),
      "2026-03-20T15:30:00.123Z")
  }

  func testCanonicalizeRfc3339InstantConvertsNonUtcOffsets() {
    XCTAssertEqual(
      SyncTimestampFormat.canonicalizeRfc3339Instant("2026-12-01T09:00:00-05:00"),
      "2026-12-01T14:00:00.000Z")
  }

  func testCanonicalizeRfc3339InstantRejectsMalformed() {
    XCTAssertNil(SyncTimestampFormat.canonicalizeRfc3339Instant("not-a-timestamp"))
    XCTAssertNil(SyncTimestampFormat.canonicalizeRfc3339Instant(""))
  }

  func testFormatSyncTimestampExample() {
    XCTAssertEqual(
      SyncTimestampFormat.formatSyncTimestamp(utc(2026, 4, 19, 8, 30, 0)),
      "2026-04-19T08:30:00.000Z")
  }

  // ── SyncTimestamp newtype ────────────────────────────────────────────

  func testSyncTimestampDisplayRoundTrips() {
    let ts = SyncTimestamp(date: utc(2026, 4, 19, 8, 30, 0))
    XCTAssertEqual(ts.asString, "2026-04-19T08:30:00.000Z")
    let parsed = SyncTimestamp.parse(ts.asString)
    XCTAssertEqual(parsed, ts)
  }

  func testSyncTimestampSerdeRoundTrips() throws {
    let ts = SyncTimestamp(date: utc(2026, 4, 19, 8, 30, 0))
    let json = String(decoding: try JSONEncoder().encode(ts), as: UTF8.self)
    XCTAssertEqual(json, "\"2026-04-19T08:30:00.000Z\"")
    let back = try JSONDecoder().decode(SyncTimestamp.self, from: Data(json.utf8))
    XCTAssertEqual(back, ts)
  }

  func testSyncTimestampOrdMatchesInstantOrd() {
    let earlier = SyncTimestamp(date: utc(2026, 1, 1, 0, 0, 0))
    let later = SyncTimestamp(date: utc(2026, 6, 15, 12, 0, 0))
    XCTAssertLessThan(earlier, later)
  }

  func testSyncTimestampParseAcceptsMicrosecond() {
    let ts = SyncTimestamp.parse("2026-03-20T15:30:00.123456Z")
    XCTAssertEqual(ts?.asString, "2026-03-20T15:30:00.123Z")
  }

  func testSyncTimestampParseRejectsNonUtc() {
    XCTAssertNil(SyncTimestamp.parse("2026-03-20T15:30:00.123+05:30"))
    XCTAssertNil(SyncTimestamp.parse("not-a-timestamp"))
  }

  func testSyncTimestampParseAcceptsExplicitZeroOffset() {
    XCTAssertEqual(
      SyncTimestamp.parse("2026-03-20T15:30:00.123+00:00")?.asString, "2026-03-20T15:30:00.123Z")
  }

  func testSyncTimestampNowRenders24Char() {
    let s = SyncTimestamp.now().asString
    XCTAssertEqual(s.count, 24)
    XCTAssertTrue(s.hasSuffix("Z"))
  }

  // ── LorvexDate / TimeOfDay newtypes ──────────────────────────────────

  func testDateParseAcceptsCanonical() {
    guard case let .success(d) = LorvexDate.parse("2026-04-19") else { return XCTFail() }
    XCTAssertEqual(d.asString, "2026-04-19")
  }

  func testDateParseRejectsNonIso() {
    XCTAssertThrowsResult(LorvexDate.parse("19/04/2026"))
    XCTAssertThrowsResult(LorvexDate.parse("2026-13-01"))
    XCTAssertThrowsResult(LorvexDate.parse(""))
    XCTAssertThrowsResult(LorvexDate.parse("2026-02-30"))
  }

  func testDateLeapYear() {
    guard case .success = LorvexDate.parse("2024-02-29") else { return XCTFail("leap year valid") }
    XCTAssertThrowsResult(LorvexDate.parse("2026-02-29"))
  }

  func testDateSerdeRoundTripsAsBareString() throws {
    guard case let .success(d) = LorvexDate.parse("2026-04-19") else { return XCTFail() }
    let json = String(decoding: try JSONEncoder().encode(d), as: UTF8.self)
    XCTAssertEqual(json, "\"2026-04-19\"")
    let round = try JSONDecoder().decode(LorvexDate.self, from: Data(json.utf8))
    XCTAssertEqual(round, d)
  }

  func testTimeOfDayParseAcceptsCanonical() {
    guard case let .success(t) = TimeOfDay.parse("09:30") else { return XCTFail() }
    XCTAssertEqual(t.asString, "09:30")
  }

  func testTimeOfDayParseRejectsInvalid() {
    XCTAssertThrowsResult(TimeOfDay.parse("24:00"))
    XCTAssertThrowsResult(TimeOfDay.parse("09:60"))
    XCTAssertThrowsResult(TimeOfDay.parse("9-30"))
    XCTAssertThrowsResult(TimeOfDay.parse(""))
    XCTAssertThrowsResult(TimeOfDay.parse("not-a-time"))
  }

  func testTimeOfDaySerdeRoundTripsAsBareString() throws {
    guard case let .success(t) = TimeOfDay.parse("17:45") else { return XCTFail() }
    let json = String(decoding: try JSONEncoder().encode(t), as: UTF8.self)
    XCTAssertEqual(json, "\"17:45\"")
    let round = try JSONDecoder().decode(TimeOfDay.self, from: Data(json.utf8))
    XCTAssertEqual(round, t)
  }

  func testTimeOfDayOrdersByMinuteNotLex() {
    guard case let .success(early) = TimeOfDay.parse("09:00"),
      case let .success(later) = TimeOfDay.parse("17:00")
    else { return XCTFail() }
    XCTAssertLessThan(early, later)
  }

  /// Assert a `Result` is a `.failure` without caring about the error payload.
  private func XCTAssertThrowsResult<T>(
    _ result: Result<T, ValidationError>, line: UInt = #line
  ) {
    if case .success = result { XCTFail("expected failure", line: line) }
  }
}
