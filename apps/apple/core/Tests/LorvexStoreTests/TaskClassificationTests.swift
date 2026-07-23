import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class TaskClassificationTests: XCTestCase {
  private static let v1 = "0000000000001_0000_a0a0a0a0a0a0a0a0"

  func testValidateTaskListExistsAcceptsExistingList() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      _ = try ListRepo.createList(db, id: ListId(trusted: "l1"), name: "L", version: Self.v1)
      try TaskClassification.validateTaskListExists(db, listId: ListId(trusted: "l1"))
    }
  }

  func testValidateTaskListExistsRejectsMissingList() throws {
    let store = try TestSupport.freshStore()
    XCTAssertThrowsError(
      try store.writer.read { db in
        try TaskClassification.validateTaskListExists(db, listId: ListId(trusted: "missing"))
      }
    ) { error in
      guard case StoreError.validation(let msg) = error else {
        return XCTFail("expected validation, got \(error)")
      }
      XCTAssertTrue(msg.contains("does not exist"), "unexpected message: \(msg)")
    }
  }

  func testValidateTaskListExistsRejectsEmptyId() throws {
    let store = try TestSupport.freshStore()
    XCTAssertThrowsError(
      try store.writer.read { db in
        try TaskClassification.validateTaskListExists(db, listId: ListId(trusted: ""))
      }
    ) { error in
      guard case StoreError.validation(let msg) = error else {
        return XCTFail("expected validation, got \(error)")
      }
      XCTAssertEqual(msg, "list_id must not be empty")
    }
  }
}
