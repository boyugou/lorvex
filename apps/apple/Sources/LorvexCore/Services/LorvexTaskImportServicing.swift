import Foundation

/// Id-preserving task restore for data import / sync apply.
public protocol LorvexTaskImporting: Sendable {
  func importRemoteTask(
    id: LorvexTask.ID,
    title: String,
    notes: String,
    aiNotes: String?,
    rawInput: String?,
    priority: LorvexTask.Priority,
    status: LorvexTask.Status,
    estimatedMinutes: Int?,
    dueDate: Date?,
    plannedDate: Date?,
    availableFrom: Date?,
    tags: [String],
    dependsOn: [LorvexTask.ID]
  ) async throws -> LorvexTask

  /// Best-effort exact metadata restore after an imported task's functional
  /// state has been recreated. Implementations with direct storage access
  /// should preserve these schema fields and re-emit the final task snapshot;
  /// simpler preview backends may keep the default no-op.
  func restoreImportedTaskMetadata(
    id: LorvexTask.ID,
    archivedAt: String?,
    deferCount: Int?,
    lastDeferReason: String?,
    lastDeferredAt: String?,
    completedAt: String?,
    createdAt: String?,
    updatedAt: String?
  ) async throws
}

public extension LorvexTaskImporting {
  func importRemoteTask(
    id: LorvexTask.ID,
    title: String,
    notes: String,
    aiNotes: String?,
    priority: LorvexTask.Priority,
    status: LorvexTask.Status,
    estimatedMinutes: Int?,
    plannedDate: Date?,
    tags: [String],
    dependsOn: [LorvexTask.ID]
  ) async throws -> LorvexTask {
    try await importRemoteTask(
      id: id,
      title: title,
      notes: notes,
      aiNotes: aiNotes,
      rawInput: nil,
      priority: priority,
      status: status,
      estimatedMinutes: estimatedMinutes,
      dueDate: nil,
      plannedDate: plannedDate,
      availableFrom: nil,
      tags: tags,
      dependsOn: dependsOn)
  }

  func restoreImportedTaskMetadata(
    id: LorvexTask.ID,
    archivedAt: String?,
    deferCount: Int?,
    lastDeferReason: String?,
    lastDeferredAt: String?,
    completedAt: String?,
    createdAt: String?,
    updatedAt: String?
  ) async throws {
    _ = id
    _ = archivedAt
    _ = deferCount
    _ = lastDeferReason
    _ = lastDeferredAt
    _ = completedAt
    _ = createdAt
    _ = updatedAt
  }
}
