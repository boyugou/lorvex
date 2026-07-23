import Foundation
import Testing

@testable import LorvexApple

// MARK: - Home/End and empty-list edges

@Test
func workspaceTaskArrowKeyMovementFirstAndLastIgnoreTheAnchor() {
  let ids = ["a", "b", "c"]

  #expect(WorkspaceTaskArrowKeyMovement.target(for: .first, anchor: "c", orderedIDs: ids) == "a")
  #expect(WorkspaceTaskArrowKeyMovement.target(for: .last, anchor: "a", orderedIDs: ids) == "c")
  #expect(WorkspaceTaskArrowKeyMovement.target(for: .first, anchor: nil, orderedIDs: ids) == "a")
}

@Test
func workspaceTaskArrowKeyMovementOnAnEmptyListAlwaysReturnsNil() {
  #expect(WorkspaceTaskArrowKeyMovement.target(for: .next, anchor: "a", orderedIDs: []) == nil)
  #expect(WorkspaceTaskArrowKeyMovement.target(for: .previous, anchor: nil, orderedIDs: []) == nil)
  #expect(WorkspaceTaskArrowKeyMovement.target(for: .first, anchor: nil, orderedIDs: []) == nil)
  #expect(WorkspaceTaskArrowKeyMovement.target(for: .last, anchor: nil, orderedIDs: []) == nil)
}

// MARK: - Previous/next: nil or absent anchor lands on the first row

@Test
func workspaceTaskArrowKeyMovementWithNoAnchorStartsAtTheFirstRowRegardlessOfDirection() {
  let ids = ["a", "b", "c"]

  #expect(WorkspaceTaskArrowKeyMovement.target(for: .next, anchor: nil, orderedIDs: ids) == "a")
  #expect(WorkspaceTaskArrowKeyMovement.target(for: .previous, anchor: nil, orderedIDs: ids) == "a")
}

@Test
func workspaceTaskArrowKeyMovementWithAnAnchorFilteredOutOfTheListStartsAtTheFirstRow() {
  let ids = ["a", "b", "c"]

  #expect(WorkspaceTaskArrowKeyMovement.target(for: .next, anchor: "z", orderedIDs: ids) == "a")
  #expect(WorkspaceTaskArrowKeyMovement.target(for: .previous, anchor: "z", orderedIDs: ids) == "a")
}

// MARK: - Previous/next: ordinary in-bounds movement

@Test
func workspaceTaskArrowKeyMovementStepsToTheAdjacentRow() {
  let ids = ["a", "b", "c"]

  #expect(WorkspaceTaskArrowKeyMovement.target(for: .next, anchor: "a", orderedIDs: ids) == "b")
  #expect(WorkspaceTaskArrowKeyMovement.target(for: .next, anchor: "b", orderedIDs: ids) == "c")
  #expect(WorkspaceTaskArrowKeyMovement.target(for: .previous, anchor: "c", orderedIDs: ids) == "b")
  #expect(WorkspaceTaskArrowKeyMovement.target(for: .previous, anchor: "b", orderedIDs: ids) == "a")
}

// MARK: - Previous/next: boundary is a no-op, never wraps

@Test
func workspaceTaskArrowKeyMovementAtTheTopOrBottomEdgeDoesNotWrapAround() {
  let ids = ["a", "b", "c"]

  #expect(WorkspaceTaskArrowKeyMovement.target(for: .previous, anchor: "a", orderedIDs: ids) == nil)
  #expect(WorkspaceTaskArrowKeyMovement.target(for: .next, anchor: "c", orderedIDs: ids) == nil)
}

@Test
func workspaceTaskArrowKeyMovementOnASingleRowListNeverMoves() {
  let ids = ["only"]

  #expect(WorkspaceTaskArrowKeyMovement.target(for: .previous, anchor: "only", orderedIDs: ids) == nil)
  #expect(WorkspaceTaskArrowKeyMovement.target(for: .next, anchor: "only", orderedIDs: ids) == nil)
  #expect(WorkspaceTaskArrowKeyMovement.target(for: .first, anchor: "only", orderedIDs: ids) == "only")
  #expect(WorkspaceTaskArrowKeyMovement.target(for: .last, anchor: "only", orderedIDs: ids) == "only")
}

// MARK: - Simulated Shift-extend sequence (the view's `keyboardEdge` bookkeeping)

/// The view layer feeds `keyboardEdge ?? selectedTaskID` back in as `anchor`
/// on every call so a Shift sequence keeps growing from where the last press
/// landed rather than recomputing from the fixed selection anchor each time.
/// This reproduces that loop directly against the pure function: three
/// consecutive Shift+Down presses from row 0 should land on rows 1, 2, 3 in
/// turn, never re-deriving from row 0 each time.
@Test
func workspaceTaskArrowKeyMovementSupportsAGrowingShiftSequenceViaTheCallersEdgeTracking() {
  let ids = ["a", "b", "c", "d"]
  var edge: String? = "a"

  edge = WorkspaceTaskArrowKeyMovement.target(for: .next, anchor: edge, orderedIDs: ids)
  #expect(edge == "b")
  edge = WorkspaceTaskArrowKeyMovement.target(for: .next, anchor: edge, orderedIDs: ids)
  #expect(edge == "c")
  edge = WorkspaceTaskArrowKeyMovement.target(for: .next, anchor: edge, orderedIDs: ids)
  #expect(edge == "d")
  // The list ends at "d" — a fourth press is a no-op, matching the boundary
  // behavior a plain arrow press has.
  edge = WorkspaceTaskArrowKeyMovement.target(for: .next, anchor: edge, orderedIDs: ids) ?? edge
  #expect(edge == "d")
}
