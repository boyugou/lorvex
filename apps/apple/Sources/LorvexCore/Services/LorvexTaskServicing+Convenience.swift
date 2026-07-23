import Foundation

/// Convenience default implementations layered on the full task service surface.
/// These forward to the ``LorvexTaskServicing`` requirements, filling in the
/// arguments a narrower caller (UI, intents, watch, importers) does not manage —
/// so a surface that edits, say, only the planned day never has to load the task
/// and re-send the deadline / defer-until columns by hand.
extension LorvexTaskServicing {
  /// Convenience overload for surfaces (UI, intents, watch, importers) that
  /// defer without a structured reason or free-text note. Forwards both `nil`.
  public func deferTask(id: LorvexTask.ID, until date: Date) async throws -> TodaySnapshot {
    try await deferTask(id: id, until: date, reason: nil, note: nil)
  }

  /// Convenience overload for callers that supply a structured `reason` but no
  /// free-text note (the reason-only defer). Forwards `note: nil`.
  public func deferTask(id: LorvexTask.ID, until date: Date, reason: String?) async throws
    -> TodaySnapshot
  {
    try await deferTask(id: id, until: date, reason: reason, note: nil)
  }

  /// Reason-only sibling of ``deferTaskReturningTask(id:until:reason:note:)``,
  /// forwarding `note: nil` for callers that carry no free-text detail.
  public func deferTaskReturningTask(id: LorvexTask.ID, until date: Date, reason: String?)
    async throws -> LorvexTask
  {
    try await deferTaskReturningTask(id: id, until: date, reason: reason, note: nil)
  }

  /// Convenience overload for surfaces that batch-defer without a reason or note.
  public func batchDeferTasks(ids: [LorvexTask.ID], until date: Date) async throws -> TodaySnapshot
  {
    try await batchDeferTasks(ids: ids, until: date, reason: nil, note: nil).snapshot
  }

  /// Convenience overload for surfaces (UI, intents, importers) that manage the
  /// planned work day but never the external deadline. It loads the task and
  /// forwards the task's current `dueDate` unchanged, so editing the planned
  /// day never silently wipes a deadline that an assistant set via MCP.
  public func updateTask(
    id: LorvexTask.ID,
    title: String,
    notes: String,
    priority: LorvexTask.Priority,
    estimatedMinutes: Int?,
    plannedDate: Date?,
    tags: [String],
    dependsOn: [LorvexTask.ID]
  ) async throws -> LorvexTask {
    let existing = try await loadTask(id: id)
    return try await updateTask(
      id: id, title: title, notes: notes, priority: priority,
      estimatedMinutes: estimatedMinutes, dueDate: existing.dueDate, plannedDate: plannedDate,
      availableFrom: existing.availableFrom, tags: tags, dependsOn: dependsOn)
  }

  /// Convenience overload for surfaces that set the deadline and planned day but
  /// not the defer-until date. It loads the task and forwards the current
  /// `availableFrom` unchanged, so a caller that does not manage the hide-until
  /// date never silently clears one an assistant set via MCP. Surfaces that DO
  /// have the task in hand should call the full method directly with an explicit
  /// `availableFrom` to avoid the extra read.
  public func updateTask(
    id: LorvexTask.ID,
    title: String,
    notes: String,
    priority: LorvexTask.Priority,
    estimatedMinutes: Int?,
    dueDate: Date?,
    plannedDate: Date?,
    tags: [String],
    dependsOn: [LorvexTask.ID]
  ) async throws -> LorvexTask {
    let existing = try await loadTask(id: id)
    return try await updateTask(
      id: id, title: title, notes: notes, priority: priority,
      estimatedMinutes: estimatedMinutes, dueDate: dueDate, plannedDate: plannedDate,
      availableFrom: existing.availableFrom, tags: tags, dependsOn: dependsOn)
  }
}
