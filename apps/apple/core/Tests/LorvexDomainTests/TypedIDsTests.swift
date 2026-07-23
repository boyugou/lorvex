import XCTest

@testable import LorvexDomain

final class TypedIDsTests: XCTestCase {
  private let validV7 = "01966a3f-7c8b-7d4e-8f3a-000000000001"

  func testTaskIdNewProducesUUIDShape() {
    let id = TaskId.new()
    XCTAssertEqual(id.asString.count, 36)
    XCTAssertTrue(EntityID.isCanonicalUUID(id.asString))
  }

  func testTaskIdParseAcceptsUUID() {
    let id = try? TaskId.parse(validV7).get()
    XCTAssertEqual(id?.asString, validV7)
  }

  func testTaskIdParseTrimsWhitespace() {
    let id = try? TaskId.parse("  \(validV7)  ").get()
    XCTAssertEqual(id?.asString, validV7)
  }

  func testTaskIdParseRejectsGarbageWithFieldLabel() {
    let result = TaskId.parse("not-a-uuid")
    guard case let .failure(.invalidFormat(field, _, actual)) = result else {
      return XCTFail("expected invalidFormat, got \(result)")
    }
    XCTAssertEqual(field, "task_id")
    XCTAssertEqual(actual, "not-a-uuid")
  }

  func testTaskIdParseRejectsEmpty() {
    XCTAssertEqual(TaskId.parse("   "), .failure(.empty("task_id")))
  }

  func testListIdAcceptsInboxSentinel() {
    let id = try? ListId.parse("inbox").get()
    XCTAssertEqual(id?.asString, "inbox")
    XCTAssertEqual(ListId.inbox(), id)
  }

  func testListIdInboxSentinelTrims() {
    let id = try? ListId.parse("  inbox  ").get()
    XCTAssertEqual(id, ListId.inbox())
  }

  func testListIdDoesNotAcceptInboxForOtherKinds() {
    let result = TaskId.parse("inbox")
    guard case .failure(.invalidFormat) = result else {
      return XCTFail("expected invalidFormat, got \(result)")
    }
  }

  func testEventTagChecklistParseUUID() {
    XCTAssertEqual(try EventId.parse(validV7).get().asString, validV7)
    XCTAssertEqual(try TagId.parse(validV7).get().asString, validV7)
    XCTAssertEqual(try ChecklistItemId.parse(validV7).get().asString, validV7)
  }

  func testSerdeRoundTripsAsBareString() throws {
    let id = try TaskId.parse(validV7).get()
    let data = try JSONEncoder().encode(id)
    let json = String(data: data, encoding: .utf8)
    // single-value container → encodes as a JSON string, not an object.
    XCTAssertEqual(json, "\"\(validV7)\"")
    let roundTrip = try JSONDecoder().decode(TaskId.self, from: data)
    XCTAssertEqual(roundTrip, id)
  }

  func testIntoStringReturnsCanonical() throws {
    let id = try TaskId.parse(validV7).get()
    XCTAssertEqual(id.asString, validV7)
  }

  func testTaskTagEdgeIdRoundTrip() {
    let task = TaskId(trusted: validV7)
    let tag = TagId(trusted: "01966a3f-7c8b-7d4e-8f3a-000000000002")
    let edge = TaskTagEdgeId(taskId: task, tagId: tag)
    XCTAssertEqual(
      edge.asString,
      "01966a3f-7c8b-7d4e-8f3a-000000000001:01966a3f-7c8b-7d4e-8f3a-000000000002")
    let dep = TaskId(trusted: "01966a3f-7c8b-7d4e-8f3a-000000000003")
    let depEdge = TaskDependencyEdgeId(taskId: task, dependsOnTaskId: dep)
    XCTAssertEqual(
      depEdge.asString,
      "01966a3f-7c8b-7d4e-8f3a-000000000001:01966a3f-7c8b-7d4e-8f3a-000000000003")
  }

  func testFromTrustedSkipsValidation() {
    let id = TaskId(trusted: "not-a-uuid")
    XCTAssertEqual(id.asString, "not-a-uuid")
  }

  func testDistinctKindsShareUnderlyingValue() {
    // Two different newtypes never unify at compile time (PartialEq is
    // per-type). We pin the shared underlying value via asString.
    let task = try? TaskId.parse(validV7).get()
    let list = try? ListId.parse(validV7).get()
    XCTAssertEqual(task?.asString, list?.asString)
  }
}
