import LorvexDomain

/// Single field-ownership source for the four independent task registers.
/// Replay copies these groups, while outbox coalescing compares the same groups
/// before carrying local provenance onto a replacement payload.
enum TaskRegisterDescriptor {
  static let contentFields = [
    "title", "body", "raw_input", "ai_notes", "list_id", "priority",
  ]

  static let scheduleFields = [
    "due_date", "estimated_minutes", "recurrence", "spawned_from",
    "spawned_from_version", "recurrence_group_id", "recurrence_instance_key",
    "canonical_occurrence_date", "last_deferred_at", "last_defer_reason",
    "planned_date", "available_from", "defer_count", "recurrence_exceptions",
  ]

  static let lifecycleFields = [
    "status", "completed_at", "recurrence_rollover_state", "recurrence_successor_id",
  ]

  static let archiveFields = ["archived_at"]

  static let contentSnapshotKeys = contentFields + ["content_version"]
  static let scheduleSnapshotKeys = scheduleFields + ["schedule_version"]
  static let lifecycleSnapshotKeys = lifecycleFields + ["lifecycle_version"]
  static let archiveSnapshotKeys = archiveFields + ["archive_version"]

  private static let identityAndMetadataKeys = [
    "id", "created_at", "updated_at", "version",
  ]

  static func knownPayload(
    from source: [String: JSONValue]
  ) -> [String: JSONValue] {
    let knownKeys = Set(
      identityAndMetadataKeys + contentSnapshotKeys + scheduleSnapshotKeys
        + lifecycleSnapshotKeys + archiveSnapshotKeys)
    return source.filter { knownKeys.contains($0.key) }
  }

  static func snapshotsMatch(
    keys: [String], lhs: [String: JSONValue], rhs: [String: JSONValue]
  ) -> Bool {
    keys.allSatisfy { key in
      guard let left = lhs[key], let right = rhs[key] else { return false }
      return left == right
    }
  }
}
