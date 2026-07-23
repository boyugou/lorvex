import LorvexDomain
import LorvexStore
import LorvexSync

extension SwiftLorvexCoreService {
  /// Narrow the core's thrown errors to the app's `LorvexCoreError`. A missing
  /// task surfaces as `.taskNotFound`; an empty-title validation surfaces as
  /// `.emptyTitle`; an outbound payload-size overflow surfaces as a typed
  /// validation error (the per-field byte budgets make this unreachable for
  /// budget-covered entities, so reaching it means a budget gap — surface it
  /// honestly rather than as an internal canonicalization string); everything
  /// else is preserved.
  ///
  /// Classification is by the core's typed error cases, never by sniffing the
  /// human-readable message text: an empty title is the typed
  /// `ValidationError.empty("title")` the workflow raises, so rewording the
  /// message cannot silently reroute the classification.
  func mapWriteError(_ error: Error) -> Error {
    if let coreError = error as? LorvexCoreError { return coreError }
    if let storeError = error as? StoreError {
      switch storeError {
      case .notFound(let entity, _) where entity == EntityName.task:
        return LorvexCoreError.taskNotFound
      default:
        return error
      }
    }
    if case ValidationError.empty("title") = error {
      return LorvexCoreError.emptyTitle
    }
    if case EnqueueError.canonicalization(.payloadTooLarge(let sizeBytes)) = error {
      return LorvexCoreError.validation(
        field: nil,
        message: "The record's combined content is too large to sync "
          + "(\(sizeBytes) bytes; the limit is \(SyncCanonicalize.maxCanonicalPayloadBytes)). "
          + "Shorten its longest text fields.")
    }
    return error
  }
}
