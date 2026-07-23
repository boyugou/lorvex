import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Ports `device_state.rs` tests verbatim.
final class DeviceStateRepoTests: XCTestCase {
  func testReadCalendarAiAccessModeDefaultsWhenMissing() throws {
    let store = try TestSupport.freshStore()
    let mode = try store.writer.write { db in
      try DeviceStateRepo.readCalendarAiAccessMode(db)
    }
    XCTAssertEqual(mode, CalendarAiAccessMode.defaultMode)
  }

  func testReadCalendarAiAccessModeAcceptsFullDetails() throws {
    let store = try TestSupport.freshStore()
    let mode = try store.writer.write { db -> CalendarAiAccessMode in
      try db.execute(
        sql: "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
        arguments: [PreferenceKeys.devCalendarAiAccessMode, "\"full_details\""])
      return try DeviceStateRepo.readCalendarAiAccessMode(db)
    }
    XCTAssertEqual(mode, CalendarAiAccessMode.fullDetails)
  }

  func testWriteCalendarAiAccessModeStoresJsonString() throws {
    let store = try TestSupport.freshStore()
    let raw = try store.writer.write { db -> String? in
      try DeviceStateRepo.writeCalendarAiAccessMode(db, mode: .fullDetails)
      XCTAssertEqual(try DeviceStateRepo.readCalendarAiAccessMode(db), .fullDetails)
      return try String.fetchOne(
        db,
        sql: "SELECT value FROM device_state WHERE key = ?1",
        arguments: [PreferenceKeys.devCalendarAiAccessMode])
    }
    XCTAssertEqual(raw, "\"full_details\"")
  }

  func testClearCalendarAiAccessModeRestoresDefault() throws {
    let store = try TestSupport.freshStore()
    let mode = try store.writer.write { db -> CalendarAiAccessMode in
      try DeviceStateRepo.writeCalendarAiAccessMode(db, mode: .fullDetails)
      try DeviceStateRepo.clearCalendarAiAccessMode(db)
      return try DeviceStateRepo.readCalendarAiAccessMode(db)
    }
    XCTAssertEqual(mode, CalendarAiAccessMode.defaultMode)
  }

  func testReadCalendarAiAccessModeRejectsLegacyAllowDenyValues() throws {
    for legacyValue in ["allow", "deny"] {
      let store = try TestSupport.freshStore()
      try store.writer.write { db in
        try db.execute(
          sql: "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
          arguments: [PreferenceKeys.devCalendarAiAccessMode, "\"\(legacyValue)\""])
        XCTAssertThrowsError(try DeviceStateRepo.readCalendarAiAccessMode(db)) { error in
          guard case let StoreError.validation(message) = error else {
            return XCTFail("expected validation error, got \(error)")
          }
          XCTAssertTrue(message.contains(legacyValue), "unexpected error: \(message)")
        }
      }
    }
  }
}
