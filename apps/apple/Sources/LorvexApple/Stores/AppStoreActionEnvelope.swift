import Foundation
import LorvexCore

extension AppStore {
  /// Run a mutating action, clearing ``errorMessage`` on success and presenting
  /// the thrown error through ``presentUserFacingError(_:)`` on failure — so a
  /// raw UUID / SQL / internal invariant never reaches the alert. This is the
  /// shared form of the do/catch envelope the action extensions otherwise
  /// repeat verbatim.
  ///
  /// Use it only where the catch path is exactly "show the error" and the
  /// success path ends by clearing the error. Methods that need a distinct
  /// failure path — a non-blocking ``toastMessage``, extra state cleanup, a
  /// returned success flag, or a typed `catch` — keep their own do/catch.
  func perform(_ body: () async throws -> Void) async {
    do {
      try await body()
      errorMessage = nil
    } catch {
      await presentUserFacingError(error)
    }
  }

  /// Run only the canonical, transactional portion of a mutation and return its
  /// committed result. Callers must keep reloads, indexing, notification
  /// scheduling, and other derived work outside this closure: once the core
  /// returns, the database mutation is durable and a later refresh failure must
  /// not be presented as if the write itself failed (which invites a duplicate
  /// retry for create operations).
  @discardableResult
  func performCanonicalMutation<Result>(
    _ body: () async throws -> Result
  ) async -> Result? {
    do {
      let result = try await body()
      errorMessage = nil
      return result
    } catch {
      await presentUserFacingError(error)
      return nil
    }
  }

  /// Reconcile derived UI/OS surfaces after a canonical mutation committed.
  /// Failure is diagnostic-only: the local database-change signal will trigger
  /// another reload, while the already-durable user action remains successful.
  func reconcileAfterCommittedMutation(
    source: String,
    _ body: () async throws -> Void
  ) async {
    do {
      try await body()
    } catch {
      let classification = UserFacingError.classify(error)
      try? await core.appendDiagnosticLog(
        source: source,
        level: "error",
        message: "Post-commit surface reconciliation failed.",
        details: classification.technicalDetail)
    }
  }
}
