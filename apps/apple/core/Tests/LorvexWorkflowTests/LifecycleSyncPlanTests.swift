import XCTest

@testable import LorvexWorkflow

/// Parity port of `lorvex_workflow::lifecycle::sync_plan` tests.
final class LifecycleSyncPlanTests: XCTestCase {
  private func edge() -> DeletedDependencyEdge {
    DeletedDependencyEdge(
      taskId: "dependent", dependsOnTaskId: "blocked",
      createdAt: "2026-05-08T00:00:00Z", version: "0000000000001_0000_ed9e000000000001")
  }

  private func tagEdge() -> CopiedTagEdge {
    CopiedTagEdge(
      taskId: "successor", tagId: "tag-a",
      version: "0000000000001_0000_7a90000000000001", createdAt: "2026-05-08T00:00:00Z")
  }

  func testCompletionPlanExposesSpawnAndRewireBuckets() {
    let result = CompletionLifecycleTransitionResult(
      updated: true,
      cancelledReminderIds: ["cancelled-reminder"],
      spawnedSuccessorId: "successor",
      spawnedSuccessorTagEdges: [tagEdge()],
      spawnedSuccessorChecklistItemIds: ["check-1"],
      spawnedSuccessorReminderIds: ["reminder-1"],
      rewiredFocusScheduleDates: ["2026-05-09"],
      rewiredCurrentFocusDates: ["2026-05-08"])

    let plan = LifecycleSyncPlan.from(completion: result)

    XCTAssertEqual(plan.status.cancelledReminderIds, ["cancelled-reminder"])
    XCTAssertEqual(plan.spawnedSuccessorId, "successor")
    XCTAssertEqual(plan.spawnedSuccessorTagEdges.count, 1)
    XCTAssertEqual(plan.spawnedSuccessorChecklistItemIds, ["check-1"])
    XCTAssertEqual(plan.spawnedSuccessorReminderIds, ["reminder-1"])
    XCTAssertEqual(plan.rewiredFocusScheduleDates, ["2026-05-09"])
    XCTAssertEqual(plan.rewiredCurrentFocusDates, ["2026-05-08"])
  }

  func testCancelPlanExposesDependencyAndSpawnBuckets() {
    let result = CancelLifecycleTransitionResult(
      updated: true,
      cancelledReminderIds: ["cancelled-reminder"],
      affectedDependentIds: ["dependent"],
      deletedDependencyEdges: [edge()],
      spawnedSuccessorId: "successor",
      spawnedSuccessorTagEdges: [tagEdge()],
      spawnedSuccessorChecklistItemIds: ["check-1"],
      spawnedSuccessorReminderIds: ["reminder-1"],
      rewiredFocusScheduleDates: ["2026-05-09"],
      rewiredCurrentFocusDates: ["2026-05-08"])

    let plan = LifecycleSyncPlan.from(cancel: result)

    XCTAssertEqual(plan.status.cancelledReminderIds, ["cancelled-reminder"])
    XCTAssertEqual(plan.status.affectedDependentIds, ["dependent"])
    XCTAssertEqual(plan.status.deletedDependencyEdges.count, 1)
    XCTAssertEqual(plan.spawnedSuccessorId, "successor")
    XCTAssertEqual(plan.spawnedSuccessorTagEdges.count, 1)
  }

  func testReopenPlanKeepsReopenedRemindersSeparateFromSuccessorCancelReminders() {
    let transition = LifecycleTransitionResult(
      sideEffects: StatusSideEffects.Result(
        cancelledReminderIds: ["status-reminder"],
        affectedDependentIds: ["status-dependent"],
        deletedDependencyEdges: [edge()]),
      spawnedSuccessorId: nil,
      spawnedSuccessorTagEdges: [],
      spawnedSuccessorChecklistItemIds: [],
      spawnedSuccessorReminderIds: [],
      cancelledSuccessorIds: ["cancelled-successor"],
      successorCancelSideEffects: SuccessorCancelSideEffects(
        cancelledReminderIds: ["successor-reminder"],
        deletedDependencyEdges: [edge()],
        affectedDependentIds: ["successor-dependent"]),
      rewiredFocusScheduleDates: ["2026-05-09"],
      rewiredCurrentFocusDates: ["2026-05-08"])
    let result = ReopenLifecycleTransitionResult(
      updated: true,
      reopenedReminderIds: ["reopened-reminder"],
      transition: transition)

    let plan = LifecycleSyncPlan.from(reopen: result)

    XCTAssertEqual(plan.reopenedReminderIds, ["reopened-reminder"])
    XCTAssertEqual(plan.status.cancelledReminderIds, ["status-reminder"])
    XCTAssertEqual(plan.cancelledSuccessorIds, ["cancelled-successor"])
    XCTAssertEqual(plan.successorCancel.cancelledReminderIds, ["successor-reminder"])
    XCTAssertEqual(plan.successorCancel.affectedDependentIds, ["successor-dependent"])
  }
}
