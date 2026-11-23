import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexWorkflow

/// A reminder time written as an instant or as a time on the user's clock
/// resolves to one stored UTC instant.
final class ReminderTimeInputTests: XCTestCase {
  private func instant(_ raw: String, timezone: String? = "America/Los_Angeles") throws -> String {
    let store = try WorkflowTestSupport.freshStore()
    return try store.writer.write { db in
      if let timezone {
        // The timezone preference is stored as a canonical JSON string (quoted).
        try db.execute(
          sql: "INSERT INTO preferences (key, value, version, updated_at) "
            + "VALUES ('timezone', ?, '0000000000000_0000_0000000000000001', ?)",
          arguments: ["\"\(timezone)\"", "2026-03-29T00:00:00Z"])
      }
      return try ReminderTimeInput.canonicalInstant(db, raw: raw)
    }
  }

  private func rejection(_ raw: String) throws -> String {
    do {
      _ = try instant(raw)
    } catch StoreError.validation(let message) {
      return message
    }
    XCTFail("expected '\(raw)' to be rejected")
    return ""
  }

  func testAnInstantIsStoredAsThatInstantWhateverTheZone() throws {
    XCTAssertEqual(try instant("2026-05-23T17:00:00Z"), "2026-05-23T17:00:00.000Z")
    XCTAssertEqual(try instant("2026-05-23T10:00:00-07:00"), "2026-05-23T17:00:00.000Z")
    XCTAssertEqual(
      try instant("2026-05-23T17:00:00Z", timezone: "Asia/Tokyo"), "2026-05-23T17:00:00.000Z")
  }

  func testATimeWithoutAnOffsetIsReadOnTheUsersClock() throws {
    // Daylight time in May (UTC-7), standard time in December (UTC-8).
    XCTAssertEqual(try instant("2026-05-23T10:00"), "2026-05-23T17:00:00.000Z")
    XCTAssertEqual(try instant("2026-12-01T10:00"), "2026-12-01T18:00:00.000Z")
    XCTAssertEqual(try instant("2026-12-01T10:00:30"), "2026-12-01T18:00:30.000Z")
    XCTAssertEqual(try instant("2026-12-01T10:00", timezone: "Asia/Tokyo"), "2026-12-01T01:00:00.000Z")
  }

  func testWithNoTimezonePreferenceTheDeviceZoneIsUsed() throws {
    let stored = try instant("2026-12-01T10:00", timezone: nil)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let expected = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 10)))
    XCTAssertEqual(stored, SyncTimestampFormat.formatSyncTimestamp(expected))
  }

  /// On 2027-03-14 clocks in Los Angeles jump from 02:00 to 03:00.
  func testATimeTheClocksSkipIsRejected() throws {
    XCTAssertTrue(try rejection("2027-03-14T02:30").contains("does not exist in America/Los_Angeles"))
    XCTAssertEqual(try instant("2027-03-14T01:59"), "2027-03-14T09:59:00.000Z")
    XCTAssertEqual(try instant("2027-03-14T03:00"), "2027-03-14T10:00:00.000Z")
  }

  /// On 2026-11-01 clocks in Los Angeles fall back from 02:00 to 01:00, so
  /// 01:30 occurs at 08:30 UTC and again at 09:30 UTC.
  func testATimeThatOccursTwiceResolvesToTheEarlierInstant() throws {
    XCTAssertEqual(try instant("2026-11-01T01:30"), "2026-11-01T08:30:00.000Z")
  }

  func testAnythingElseIsRejectedWithBothAcceptedForms() throws {
    for raw in [
      "not-a-time", "2026-05-23", "10:00", "2026-05-23 10:00", "2026-05-23T24:00",
      "2026-05-23T10:60", "2026-02-30T10:00", "2026-05-23T10", "2026-05-23T1:00",
      "2026-05-23T10:00:00.5", "2026-05-23T10:00+0700",
    ] {
      let message = try rejection(raw)
      XCTAssertTrue(message.contains("YYYY-MM-DDTHH:MM"), raw)
      XCTAssertTrue(message.contains("RFC 3339"), raw)
    }
  }
}
