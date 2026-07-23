import XCTest

@testable import LorvexSync

/// Ports `lorvex-sync/src/composite_edge/tests.rs`.
final class CompositeEdgeTests: XCTestCase {
  func testSplitRequiresExactlyOneSeparatorAndNonEmptyHalves() {
    let ok = CompositeEdge.splitCompositeEdgeId("task:tag")
    guard case .success(let (l, r)) = ok else { return XCTFail("expected success") }
    XCTAssertEqual(l, "task")
    XCTAssertEqual(r, "tag")

    for invalid in ["", "task", "task:", ":tag", "task:tag:extra"] {
      guard case .failure = CompositeEdge.splitCompositeEdgeId(invalid) else {
        return XCTFail("\(invalid) must be rejected")
      }
    }
  }

  func testRemapRewritesEitherHalfOnlyForValidIds() {
    XCTAssertEqual(
      try? CompositeEdge.remapCompositeEdgeId("task:tag", oldPart: "task", newPart: "task-2").get(),
      "task-2:tag")
    XCTAssertEqual(
      try? CompositeEdge.remapCompositeEdgeId("task:tag", oldPart: "tag", newPart: "tag-2").get(),
      "task:tag-2")
    // No match → success(nil).
    let noMatch = CompositeEdge.remapCompositeEdgeId("task:tag", oldPart: "missing", newPart: "x")
    guard case .success(let value) = noMatch else { return XCTFail("expected success") }
    XCTAssertNil(value)
    // Invalid id → failure.
    guard case .failure = CompositeEdge.remapCompositeEdgeId(
      "task:tag:extra", oldPart: "tag", newPart: "x")
    else { return XCTFail("expected failure") }
  }
}
