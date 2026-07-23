import Foundation

/// Narrow capability for the lossless Apple-native task-graph restore.
///
/// Unlike the portable task importer, this capability materializes an already
/// finalized history graph exactly as exported. It is intentionally separate
/// from ``LorvexNativeImportServicing`` so alternate cores can keep supporting
/// portable migration without claiming they can preserve task register clocks
/// and recurrence lineage.
public protocol LorvexNativeTaskGraphImportServicing: Sendable {
  /// Restore `snapshot` in one transaction when the local task domain is fresh
  /// and every referenced list/tag root already exists. Returns
  /// ``NativeTaskGraphImportDisposition/portableFallback`` when exact restore is
  /// unsafe; the caller then uses the existing portable migration path.
  func importNativeTaskGraphIfFresh(
    _ snapshot: NativeTaskGraphSnapshot
  ) async throws -> NativeTaskGraphImportDisposition
}

public enum NativeTaskGraphImportDisposition: Sendable, Equatable {
  case imported(taskCount: Int)
  case portableFallback
}

public enum NativeTaskGraphImportError: LocalizedError, Sendable, Equatable {
  case invalidGraph(String)

  public var errorDescription: String? {
    switch self {
    case .invalidGraph(let detail):
      return "The Apple-native task graph is invalid: \(detail)"
    }
  }
}
