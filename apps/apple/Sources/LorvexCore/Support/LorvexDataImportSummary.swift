import Foundation

/// Something an import could not restore completely: a record it skipped, a
/// detail a restored task came back without, or a whole category that failed
/// as one unit. Issues are collected rather than thrown, so one bad record
/// never aborts the rest of the import.
public struct LorvexImportIssue: Sendable, Equatable {
  /// The record an issue is about.
  public enum Record: Sendable, Equatable {
    /// The whole category, when it restores as one unit (an exact task graph,
    /// the calendar bundle) and that unit failed.
    case wholeCategory
    /// One record, by its id in the backup and the name people know it by: a
    /// task's title; a list's, tag's, or habit's name; a memory's or
    /// preference's key; or, for a task–event link, its task's title. `name`
    /// is nil when the backup holds no name for the record.
    case named(id: String, name: String?)
    /// One day's record (a daily review or briefing), by its `yyyy-MM-dd` key.
    case day(String)
  }

  /// A detail of a task that can fail to restore while the task itself does.
  public enum Part: Sendable, Equatable, CaseIterable {
    case plannedTime
    case list
    case checklist
    case reminders
    case recurrence
    case dependencies
    /// A cancelled or in-progress status; without it the task is open.
    case status
    /// When the task was created, completed, or archived, and its defer
    /// history.
    case history
  }

  /// What happened to the record.
  public enum Outcome: Sendable, Equatable {
    /// The record was not restored.
    case notImported
    /// The record was restored without this detail.
    case restoredWithout(Part)
  }

  public var category: LorvexDataExportCategory
  public var record: Record
  public var outcome: Outcome
  /// The English finding behind the issue, for the private import log and for
  /// tests; never shown to people.
  public var detail: String

  public init(
    category: LorvexDataExportCategory, record: Record, outcome: Outcome, detail: String
  ) {
    self.category = category
    self.record = record
    self.outcome = outcome
    self.detail = detail
  }

  /// The record's id in the backup (a day record's key), or nil for a whole
  /// category.
  public var recordID: String? {
    switch record {
    case .wholeCategory: nil
    case .named(let id, _): id
    case .day(let day): day
    }
  }
}

/// Per-category outcome of an applied import.
///
/// `imported` counts records written this run; `skipped` counts records already
/// present and left untouched (the idempotency signal — re-importing the same
/// file yields `imported == 0, skipped == N`).
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

/// The result of applying an import plan: per-category written and skipped
/// counts with every issue met along the way, or, when the backup as a whole
/// was refused before anything was written, the reason it was refused.
public struct LorvexImportSummary: Sendable, Equatable {
  public var results: [LorvexImportCategoryResult]
  public var issues: [LorvexImportIssue]
  /// Why the whole backup was refused before anything was written, or nil
  /// when the import ran. A refused import has no results and no issues.
  public var rejection: LorvexDataImporter.ImportError?

  /// An import that ran.
  public init(results: [LorvexImportCategoryResult], issues: [LorvexImportIssue]) {
    self.results = results
    self.issues = issues
    self.rejection = nil
  }

  /// A backup refused as a whole before anything was written.
  public init(rejection: LorvexDataImporter.ImportError) {
    self.results = []
    self.issues = []
    self.rejection = rejection
  }

  public var totalImported: Int { results.reduce(0) { $0 + $1.imported } }
  public var totalSkipped: Int { results.reduce(0) { $0 + $1.skipped } }
}
