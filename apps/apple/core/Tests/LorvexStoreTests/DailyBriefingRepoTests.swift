import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class DailyBriefingRepoTests: XCTestCase {
  private typealias Repo = DailyBriefingRepo

  private let v1 = "0001000000000_0001_de1cea0000000000"
  private let v2 = "0001000000001_0001_de1cea0000000000"
  private let older = "0000999999999_0001_de1cea0000000000"

  private func readRow(_ db: Database, _ date: String) throws -> (String, String?, String)? {
    try Row.fetchOne(
      db, sql: "SELECT briefing, timezone, version FROM daily_briefings WHERE date = ?",
      arguments: [date]
    ).map { ($0[0], $0[1], $0[2]) }
  }

  func testUpsertCreatesThenReplacesTextAndKeepsTimezone() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try Repo.upsertBriefing(
        db, date: "2026-04-19", briefing: "Two meetings, then the report.",
        timezone: "America/New_York", version: self.v1, now: "2026-04-19T08:00:00Z")
      try Repo.upsertBriefing(
        db, date: "2026-04-19", briefing: "The report moved to tomorrow.",
        timezone: "Asia/Shanghai", version: self.v2, now: "2026-04-19T09:00:00Z")
      let row = try XCTUnwrap(try self.readRow(db, "2026-04-19"))
      XCTAssertEqual(row.0, "The report moved to tomorrow.")
      XCTAssertEqual(row.1, "America/New_York", "the day's timezone is fixed at creation")
      XCTAssertEqual(row.2, self.v2)
      XCTAssertEqual(try Repo.briefing(db, date: "2026-04-19"), "The report moved to tomorrow.")
    }
  }

  func testUpsertRejectsBlankTextAndStaleVersion() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertThrowsError(
        try Repo.upsertBriefing(
          db, date: "2026-04-19", briefing: " \n ", timezone: "UTC", version: self.v1,
          now: "2026-04-19T08:00:00Z"))
      XCTAssertNil(try Repo.briefing(db, date: "2026-04-19"))

      try Repo.upsertBriefing(
        db, date: "2026-04-19", briefing: "Current", timezone: "UTC", version: self.v2,
        now: "2026-04-19T08:00:00Z")
      XCTAssertThrowsError(
        try Repo.upsertBriefing(
          db, date: "2026-04-19", briefing: "Stale", timezone: "UTC", version: self.v1,
          now: "2026-04-19T09:00:00Z")
      ) { error in
        guard case StoreError.staleVersion = error else {
          return XCTFail("expected staleVersion, got \(error)")
        }
      }
      XCTAssertEqual(try Repo.briefing(db, date: "2026-04-19"), "Current")
    }
  }

  func testUpsertRejectsTextOverThePayloadBudget() throws {
    let store = try TestSupport.freshStore()
    let oversized = String(repeating: "a", count: PayloadByteBudget.dayPlanTextEscapedBytes + 1)
    try store.writer.write { db in
      XCTAssertThrowsError(
        try Repo.upsertBriefing(
          db, date: "2026-04-19", briefing: oversized, timezone: "UTC", version: self.v1,
          now: "2026-04-19T08:00:00Z"))
    }
  }

  func testSyncUpsertGreaterRejectsEqualAndLowerVersions() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertTrue(
        try Repo.syncUpsertBriefing(
          db, date: "2026-04-19", briefing: "baseline", timezone: "UTC", version: self.v1,
          createdAt: "2026-04-19T08:00:00Z", updatedAt: "2026-04-19T08:00:00Z", versionCmp: ">"))
      XCTAssertFalse(
        try Repo.syncUpsertBriefing(
          db, date: "2026-04-19", briefing: "attempted-equal", timezone: "UTC", version: self.v1,
          createdAt: "2026-04-19T08:00:00Z", updatedAt: "2026-04-19T09:00:00Z", versionCmp: ">"))
      XCTAssertFalse(
        try Repo.syncUpsertBriefing(
          db, date: "2026-04-19", briefing: "attempted-older", timezone: "UTC",
          version: self.older, createdAt: "2026-04-19T08:00:00Z",
          updatedAt: "2026-04-19T09:00:00Z", versionCmp: ">"))
      XCTAssertEqual(try Repo.briefing(db, date: "2026-04-19"), "baseline")

      XCTAssertTrue(
        try Repo.syncUpsertBriefing(
          db, date: "2026-04-19", briefing: "newer-wins", timezone: "Europe/Paris",
          version: self.v2, createdAt: "2026-04-19T08:00:00Z",
          updatedAt: "2026-04-19T10:00:00Z", versionCmp: ">"))
      let row = try XCTUnwrap(try self.readRow(db, "2026-04-19"))
      XCTAssertEqual(row.0, "newer-wins")
      XCTAssertEqual(row.1, "Europe/Paris", "sync replaces every column from the envelope")
      XCTAssertEqual(row.2, self.v2)
    }
  }

  func testSyncUpsertGreaterOrEqualAcceptsEqualVersionReplay() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      _ = try Repo.syncUpsertBriefing(
        db, date: "2026-04-20", briefing: "baseline", timezone: "UTC", version: self.v1,
        createdAt: "2026-04-20T08:00:00Z", updatedAt: "2026-04-20T08:00:00Z", versionCmp: ">")
      XCTAssertTrue(
        try Repo.syncUpsertBriefing(
          db, date: "2026-04-20", briefing: "rehydrated", timezone: "UTC", version: self.v1,
          createdAt: "2026-04-20T08:00:00Z", updatedAt: "2026-04-20T08:00:00Z",
          versionCmp: ">="))
      XCTAssertEqual(try Repo.briefing(db, date: "2026-04-20"), "rehydrated")
      XCTAssertFalse(
        try Repo.syncUpsertBriefing(
          db, date: "2026-04-20", briefing: "attempted-older", timezone: "UTC",
          version: self.older, createdAt: "2026-04-20T08:00:00Z",
          updatedAt: "2026-04-20T08:00:00Z", versionCmp: ">="))
    }
  }

  func testSyncUpsertRejectsAnUnknownComparison() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertThrowsError(
        try Repo.syncUpsertBriefing(
          db, date: "2026-04-20", briefing: "x", timezone: "UTC", version: self.v1,
          createdAt: "2026-04-20T08:00:00Z", updatedAt: "2026-04-20T08:00:00Z",
          versionCmp: "; DROP TABLE tasks"))
    }
  }

  func testDeleteRemovesTheRow() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try Repo.upsertBriefing(
        db, date: "2026-04-21", briefing: "Short day.", timezone: "UTC", version: self.v1,
        now: "2026-04-21T08:00:00Z")
      XCTAssertTrue(try Repo.deleteBriefing(db, date: "2026-04-21"))
      XCTAssertFalse(try Repo.deleteBriefing(db, date: "2026-04-21"))
      XCTAssertNil(try Repo.briefing(db, date: "2026-04-21"))
    }
  }
}
