import LorvexDomain

extension PayloadShadow {
  private static let taskWireKeys = [
    "id", "title", "body", "raw_input", "ai_notes",
    "status", "list_id", "priority", "due_date", "estimated_minutes",
    "recurrence", "recurrence_exceptions", "spawned_from", "spawned_from_version",
    "recurrence_group_id", "canonical_occurrence_date", "created_at", "updated_at",
    "completed_at", "last_deferred_at", "planned_date", "available_from",
    "defer_count", "last_defer_reason", "recurrence_instance_key",
    "archived_at", "content_version", "schedule_version", "lifecycle_version",
    "archive_version", "recurrence_rollover_state", "recurrence_successor_id",
    "version",
  ]

  private static let aiChangelogWireKeys = [
    "timestamp", "operation", "entity_type", "entity_id", "entity_ids",
    "summary", "initiated_by", "mcp_tool", "source_device_id", "before_json",
    "after_json", "retention_epoch", "version",
  ]
  private static let entityRedirectWireKeys = [
    "source_type", "source_id", "target_id", "version",
  ]

  private static let taskSyntheticWireKeys = ["recurrence_exceptions"]
  private static let aiChangelogSyntheticWireKeys = ["entity_ids", "version"]
  private static let aiChangelogLocalOnlyKeys = [
    // `cloud_presence_possible` is intentionally not a schema column anymore;
    // keep the old reserved spelling denylisted so a crafted future payload
    // cannot preserve and relay device-local evidence through the shadow.
    "id", "retention_account_identifier", "cloud_presence_possible",
  ]

  /// Canonical upsert wire keys understood by this runtime. Unlike
  /// ``ownedKeysForEntity(_:)``, this excludes derived-local storage keys.
  static func wireKeysForEntity(_ entityType: String) -> [String] {
    guard let kind = EntityKind.parse(entityType) else { return [] }
    if let descriptor = SyncEntityDescriptor.descriptor(for: kind) {
      return descriptor.wireKeys
    }
    switch kind {
    case .task:
      return taskWireKeys
    case .aiChangelog:
      return aiChangelogWireKeys
    case .entityRedirect:
      return entityRedirectWireKeys
    case .list, .tag, .taskReminder, .taskChecklistItem, .habitReminderPolicy, .memory,
      .calendarSeriesCutover,
      .preference, .taskTag, .taskDependency, .taskCalendarEventLink,
      .habitCompletion, .habit, .calendarEvent, .dailyReview, .currentFocus, .focusSchedule:
      return SyncEntityDescriptor.require(kind).wireKeys
    case .deviceState, .importSession:
      return []
    }
  }

  /// Wire keys materialized outside a 1:1 base-table column projection.
  static func syntheticWireKeysForEntity(_ entityType: String) -> [String] {
    guard let kind = EntityKind.parse(entityType) else { return [] }
    if let descriptor = SyncEntityDescriptor.descriptor(for: kind) {
      return descriptor.syntheticKeys
    }
    switch kind {
    case .task:
      return taskSyntheticWireKeys
    case .aiChangelog:
      return aiChangelogSyntheticWireKeys
    case .entityRedirect:
      return []
    case .list, .tag, .taskReminder, .taskChecklistItem, .habitReminderPolicy, .memory,
      .calendarSeriesCutover,
      .preference, .taskTag, .taskDependency, .taskCalendarEventLink,
      .habitCompletion, .habit, .calendarEvent, .dailyReview, .currentFocus, .focusSchedule:
      return SyncEntityDescriptor.require(kind).syntheticKeys
    case .deviceState, .importSession:
      return []
    }
  }

  /// Static allowlist of locally-known JSON keys per entity kind.
  ///
  /// Both the merge overlay path and the shadow-write path consult this table
  /// to decide which keys are owned by the local schema (and may be dropped when
  /// absent from a fresh payload) and which are forward-compat unknowns the
  /// shadow row preserves verbatim. The payload-shadow structural tests lock
  /// this allowlist to each entity's declared wire projection while permitting
  /// explicit derived-local and generated storage columns to stay off the wire.
  ///
  /// Dispatch via `EntityKind` so a typo in a runtime string surfaces as a
  /// parse failure (the empty fallback) rather than silently dumping every
  /// shadow field into the "unknown" bucket.
  ///
  /// Migrated entities derive their owned keys from their
  /// ``SyncEntityDescriptor``; the `switch` below serves the entities not yet
  /// migrated.
  static func ownedKeysForEntity(_ entityType: String) -> [String] {
    guard let kind = EntityKind.parse(entityType) else {
      return []
    }
    if let descriptor = SyncEntityDescriptor.descriptor(for: kind) {
      return descriptor.shadowConsumedKeys
    }
    switch kind {
    case .task:
      return taskWireKeys
    case .aiChangelog:
      // Identity is envelope-only; account routing is device-local; the removed
      // cloud-presence spelling remains reserved. Strip all three if encountered
      // so a malicious/future payload cannot relay them as unknowns.
      return aiChangelogLocalOnlyKeys + aiChangelogWireKeys
    case .entityRedirect:
      return entityRedirectWireKeys
    case .list, .tag, .taskReminder, .taskChecklistItem, .habitReminderPolicy, .memory,
      .calendarSeriesCutover,
      .preference, .taskTag, .taskDependency, .taskCalendarEventLink,
      .habitCompletion, .habit, .calendarEvent, .dailyReview, .currentFocus, .focusSchedule:
      // Migrated to ``SyncEntityDescriptor``: served by the descriptor consult
      // above, so these arms are unreachable at runtime. Kept (deriving from the
      // same descriptor) purely so the switch stays exhaustive and a NEW
      // `EntityKind` still forces a compile error here.
      return SyncEntityDescriptor.require(kind).shadowConsumedKeys
    case .deviceState, .importSession:
      // Local-only kinds never participate in payload-shadow forward-compat
      // preservation — they are not synced.
      return []
    }
  }
}
