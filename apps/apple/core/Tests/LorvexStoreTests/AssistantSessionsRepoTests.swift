import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class AssistantSessionsRepoTests: XCTestCase {
  func testReadIsEmptyBeforeAnyClient() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.read { db in try AssistantSessionsRepo.read(db) }
    XCTAssertEqual(rows, [])
  }

  func testRecordingMovesTheClientToTheFrontAndUpdatesIt() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [AssistantSessionRow] in
      try AssistantSessionsRepo.recordActivity(
        db, name: "claude-ai", title: nil, version: "0.1.0", at: "2026-09-28T10:00:00.000Z")
      try AssistantSessionsRepo.recordActivity(
        db, name: "claude-code", title: "Claude Code", version: "2.1.0",
        at: "2026-09-28T11:00:00.000Z")
      try AssistantSessionsRepo.recordActivity(
        db, name: "claude-ai", title: nil, version: "0.2.0", at: "2026-09-28T12:00:00.000Z")
      return try AssistantSessionsRepo.read(db)
    }
    XCTAssertEqual(
      rows,
      [
        AssistantSessionRow(
          name: "claude-ai", title: nil, version: "0.2.0", lastActiveAt: "2026-09-28T12:00:00.000Z"),
        AssistantSessionRow(
          name: "claude-code", title: "Claude Code", version: "2.1.0",
          lastActiveAt: "2026-09-28T11:00:00.000Z"),
      ])
  }

  func testRecordKeepsOnlyTheMostRecentClients() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [AssistantSessionRow] in
      for index in 0..<(AssistantSessionsRepo.maxClients + 3) {
        try AssistantSessionsRepo.recordActivity(
          db, name: "client-\(index)", title: nil, version: nil,
          at: "2026-09-28T10:00:00.000Z")
      }
      return try AssistantSessionsRepo.read(db)
    }
    XCTAssertEqual(rows.count, AssistantSessionsRepo.maxClients)
    XCTAssertEqual(rows.first?.name, "client-\(AssistantSessionsRepo.maxClients + 2)")
  }

  func testBlankNamesRecordNothingAndLongFieldsAreBounded() throws {
    let store = try TestSupport.freshStore()
    let long = String(repeating: "x", count: 500)
    let rows = try store.writer.write { db -> [AssistantSessionRow] in
      try AssistantSessionsRepo.recordActivity(
        db, name: "  ", title: "Ignored", version: nil, at: "2026-09-28T10:00:00.000Z")
      try AssistantSessionsRepo.recordActivity(
        db, name: " \(long) ", title: "  ", version: long, at: "2026-09-28T10:00:00.000Z")
      return try AssistantSessionsRepo.read(db)
    }
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows[0].name.count, AssistantSessionsRepo.maxFieldLength)
    XCTAssertNil(rows[0].title)
    XCTAssertEqual(rows[0].version?.count, AssistantSessionsRepo.maxFieldLength)
  }

  func testMalformedValueReadsAsEmptyAndIsReplacedByTheNextRecord() throws {
    let store = try TestSupport.freshStore()
    let (before, after) = try store.writer.write { db -> ([AssistantSessionRow], [AssistantSessionRow]) in
      try db.execute(
        sql: "INSERT INTO device_state (key, value) VALUES (?1, ?2)",
        arguments: [PreferenceKeys.devMcpClientSessions, "not json"])
      let before = try AssistantSessionsRepo.read(db)
      try AssistantSessionsRepo.recordActivity(
        db, name: "claude-code", title: nil, version: nil, at: "2026-09-28T10:00:00.000Z")
      return (before, try AssistantSessionsRepo.read(db))
    }
    XCTAssertEqual(before, [])
    XCTAssertEqual(after.map(\.name), ["claude-code"])
  }
}
