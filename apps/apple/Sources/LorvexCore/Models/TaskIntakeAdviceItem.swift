import Foundation

/// One deterministic task-intake nudge surfaced after a task is captured
/// (e.g. via `batch_create_tasks` with `include_advice`). Mirrors the core
/// `TaskCreateAdvice` output: a stable `code` (`missing_estimate`,
/// `missing_planned_date`, `likely_duplicate_title`), a `severity`, a
/// human-readable `message`, and — for the duplicate-title nudge — the ids of
/// the existing active tasks that look like duplicates (empty otherwise).
public struct TaskIntakeAdviceItem: Sendable, Equatable {
  public let code: String
  public let severity: String
  public let message: String
  public let relatedTaskIDs: [String]

  public init(
    code: String, severity: String, message: String, relatedTaskIDs: [String] = []
  ) {
    self.code = code
    self.severity = severity
    self.message = message
    self.relatedTaskIDs = relatedTaskIDs
  }
}
