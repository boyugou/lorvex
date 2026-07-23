import LorvexCore

extension MobileStore {
  /// Run only the canonical, transactional portion of a mutation and return its
  /// committed result. Derived reloads belong in
  /// ``reconcileAfterCommittedMutation(source:_:)`` so a post-commit read failure
  /// cannot make a successful create look retryable and produce a duplicate.
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

  /// Best-effort reload of UI/OS projections after the authoritative database
  /// mutation committed. Preserve the mutation's success result and record the
  /// refresh failure locally for diagnostics; the database-change relay will
  /// schedule another reconciliation pass.
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
