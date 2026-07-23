import Foundation

/// A single record that could not be restored, kept so one bad row never aborts
/// the whole import. `recordRef` is a human-readable handle (a task id, memory
/// key, review date, or session id) and `message` the failure reason.
public struct LorvexImportError: Sendable, Equatable {
  public var category: LorvexDataExportCategory
  public var recordRef: String
  public var message: String

  public init(category: LorvexDataExportCategory, recordRef: String, message: String) {
    self.category = category
    self.recordRef = recordRef
    self.message = message
  }
}

/// Per-category outcome of an applied import.
///
/// `imported` counts records written this run; `skipped` counts records already
/// present and left untouched (the idempotency signal — re-importing the same
/// file yields `imported == 0, skipped == N`). `errors` collects per-record
/// failures rather than throwing them, so the rest of the file still imports.
public struct LorvexImportCategoryResult: Identifiable, Sendable, Equatable {
  public var category: LorvexDataExportCategory
  public var imported: Int
  public var skipped: Int

  public var id: String { category.rawValue }

  public init(category: LorvexDataExportCategory, imported: Int, skipped: Int) {
    self.category = category
    self.imported = imported
    self.skipped = skipped
  }
}

/// The result of applying an import plan: per-category written/skipped counts
/// plus every per-record error encountered. Errors are collected, not thrown —
/// a single malformed record does not abort the import.
public struct LorvexImportSummary: Sendable, Equatable {
  public var results: [LorvexImportCategoryResult]
  public var errors: [LorvexImportError]

  public init(results: [LorvexImportCategoryResult], errors: [LorvexImportError]) {
    self.results = results
    self.errors = errors
  }

  public var totalImported: Int { results.reduce(0) { $0 + $1.imported } }
  public var totalSkipped: Int { results.reduce(0) { $0 + $1.skipped } }
}
