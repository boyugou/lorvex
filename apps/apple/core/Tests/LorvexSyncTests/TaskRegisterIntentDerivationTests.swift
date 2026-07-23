import LorvexDomain
import XCTest

@testable import LorvexSync

final class TaskRegisterIntentDerivationTests: XCTestCase {
  private func payload(
    title: String = "Before",
    dueDate: JSONValue = .null,
    contentVersion: String = "content-1",
    scheduleVersion: String = "schedule-1",
    lifecycleVersion: String = "lifecycle-1",
    archiveVersion: String = "archive-1"
  ) -> JSONValue {
    var object = Dictionary(
      uniqueKeysWithValues:
        (TaskRegisterDescriptor.contentFields
          + TaskRegisterDescriptor.scheduleFields
          + TaskRegisterDescriptor.lifecycleFields
          + TaskRegisterDescriptor.archiveFields)
        .map { ($0, JSONValue.null) })
    object["title"] = .string(title)
    object["due_date"] = dueDate
    object["content_version"] = .string(contentVersion)
    object["schedule_version"] = .string(scheduleVersion)
    object["lifecycle_version"] = .string(lifecycleVersion)
    object["archive_version"] = .string(archiveVersion)
    return .object(object)
  }

  func testDerivesTheUnionOfEveryClockedValueGroup() throws {
    let before = payload()
    let after = payload(
      title: "After",
      dueDate: .string("2026-10-01"),
      contentVersion: "content-2",
      scheduleVersion: "schedule-2")

    XCTAssertEqual(
      try TaskRegisterIntent.authoredRegisters(between: before, and: after),
      [.content, .schedule])
  }

  func testRejectsAValueGroupChangeWithoutItsClock() throws {
    XCTAssertThrowsError(
      try TaskRegisterIntent.authoredRegisters(
        between: payload(), and: payload(title: "Unclocked"))
    ) { error in
      XCTAssertEqual(error as? TaskRegisterIntentError, .unstampedRegister("content_version"))
    }
  }
}
