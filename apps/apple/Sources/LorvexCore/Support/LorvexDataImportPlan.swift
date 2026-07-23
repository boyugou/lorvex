import Foundation

/// One row of an import content plan: a category, how many records the file
/// carries for it, and whether this app can restore that category idempotently.
///
/// `recordCount` is a content count — how many records the file holds for the
/// category — not a prediction of how many a restore will write. Apply is
/// non-destructive (skip-if-exists, tombstone-guarded), so a supported record
/// already present or tombstoned locally is skipped at apply time; the plan does
/// not diff the target database, so it cannot know which records that will be.
///
/// `isSupported == false` means the category has no ID/key-preserving restore
/// primitive yet, so the importer counts the records but never writes them
/// (writing via a `create*` path would duplicate on re-import). Those records
/// are surfaced separately so the user sees what the file holds versus what this
/// version is able to restore.
public struct LorvexImportPlanEntry: Identifiable, Sendable, Equatable {
  public var category: LorvexDataExportCategory
  public var recordCount: Int
  public var isSupported: Bool
  /// True when this user-facing category carries restorable internal rows that
  /// deliberately do not inflate `recordCount`. Calendar-series deleted
  /// boundaries and native task tombstone/payload-shadow state are such
  /// dependencies: a backup containing only sync barriers must still enable
  /// Apply even though it displays zero live records.
  public var hasInternalDependencyData: Bool

  public var id: String { category.rawValue }

  public init(
    category: LorvexDataExportCategory, recordCount: Int, isSupported: Bool,
    hasInternalDependencyData: Bool = false
  ) {
    self.category = category
    self.recordCount = recordCount
    self.isSupported = isSupported
    self.hasInternalDependencyData = hasInternalDependencyData
  }
}

/// The result of decoding an import file and counting its contents, without
/// writing anything.
///
/// `entries` lists every category the file carries (in `LorvexDataExportCategory`
/// declaration order), each tagged supported-or-deferred. Building a plan performs
/// no service calls: it is a pure decode plus per-category count, so presenting a
/// plan can never mutate the database and never diffs it. The plan therefore
/// reports what the file *contains*, not what a restore will write — apply skips
/// already-present and tombstoned records. The only write path is
/// `LorvexDataImporter.apply` invoked after the user confirms.
public struct LorvexImportPlan: Sendable, Equatable {
  public var entries: [LorvexImportPlanEntry]

  public init(entries: [LorvexImportPlanEntry]) {
    self.entries = entries
  }

  /// Records the file carries in categories that have an id-preserving restore
  /// primitive. A content count and an upper bound on what a restore writes, not
  /// a prediction: apply skips any record already present or tombstoned locally.
  public var supportedRecordCount: Int {
    entries.filter(\.isSupported).reduce(0) { $0 + $1.recordCount }
  }

  /// Total records the file holds for categories with no idempotent restore
  /// path yet — counted, never written.
  public var deferredRecordCount: Int {
    entries.filter { !$0.isSupported }.reduce(0) { $0 + $1.recordCount }
  }

  /// True when the file carries at least one record in a restorable category.
  /// Gates the Import button. Reflects the file's contents, not whether the
  /// restore will write — every such record may still be skipped as
  /// already-present or tombstoned.
  public var hasSupportedRecords: Bool {
    entries.contains {
      $0.isSupported && ($0.recordCount > 0 || $0.hasInternalDependencyData)
    }
  }
}
