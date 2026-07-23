import Foundation

/// One entry in a task's read-only defer trail, reconstructed from the
/// append-only `ai_changelog` (no dedicated column or child table backs it).
///
/// `deferredAt` and `initiatedBy` are system-controlled (the changelog row's
/// timestamp and actor). `structuredReason` is the coarse defer category
/// recorded for that specific defer (a `DeferReason` raw value, or `nil` when
/// none was supplied). `note` is the optional free-text detail the assistant or
/// user attached to that defer; it is user-controlled text and must be fenced
/// before it appears in an MCP response.
public struct TaskDeferHistoryEntry: Sendable, Equatable {
  public let deferredAt: String
  public let structuredReason: String?
  public let note: String?
  public let initiatedBy: String?

  public init(
    deferredAt: String,
    structuredReason: String? = nil,
    note: String? = nil,
    initiatedBy: String? = nil
  ) {
    self.deferredAt = deferredAt
    self.structuredReason = structuredReason
    self.note = note
    self.initiatedBy = initiatedBy
  }
}
