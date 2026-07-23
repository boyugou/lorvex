import LorvexCore
import LorvexSync

extension CloudSyncEngineCoordinator {
  /// Reset only the exact durable traversal observed by the caller. Core repeats
  /// the identity check inside the SQLite transaction, so a newer cross-process
  /// traversal cannot be replaced between this read and the atomic reset.
  func resetGenerationTraversalAfterInvalidCursor(
    sync: any EnvelopeSyncServicing, boundary: CloudTraversalBoundary,
    requireFullReseed: Bool
  ) throws {
    let state = try sync.cloudTraversalState(
      accountIdentifier: boundary.accountIdentifier,
      zoneIdentifier: boundary.zoneIdentifier)
    guard let progress = state.progress, progress.boundary == boundary else {
      throw CloudTraversalStateError.traversalBoundaryMismatch
    }
    try sync.resetCloudTraversalAfterInvalidCursor(
      boundary: boundary,
      traversalIdentifier: progress.traversalIdentifier,
      requireFullReseed: requireFullReseed)
  }
}
