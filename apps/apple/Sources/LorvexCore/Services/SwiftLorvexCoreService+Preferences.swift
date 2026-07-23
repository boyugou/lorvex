import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  // MARK: - Preferences

  public func getAllPreferences() async throws -> PreferencesSnapshot {
    try read { db in
      PreferencesSnapshot(values: try Self.readPreferences(db))
    }
  }

  public func getPreference(key: String) async throws -> String? {
    try read { db in
      if PreferenceKeys.isControlPlanePreference(key) {
        return ChangelogRetentionPolicy.read(db).wireValue
      }
      if key == PreferenceKeys.devCalendarAiAccessMode {
        return try DeviceStateRepo.readCalendarAiAccessMode(db).asString
      }
      return try String.fetchOne(
        db, sql: "SELECT value FROM preferences WHERE key = ?1", arguments: [key])
    }
  }

  /// Upsert a preference through `PreferenceRepo.setPreference`, funneled via
  /// the `+WriteSurface` adapter (one HLC version, immediate transaction,
  /// `local_change_seq` bump). The `value` is stored as canonical JSON
  /// (`stored(value:)`) so reads via `getPreference` / `preferenceString`
  /// round-trip; the returned string is the caller's original plain `value`.
  public func setPreference(key: String, value: String) async throws -> String {
    try withWrite { db, hlc, deviceId in
      if PreferenceKeys.isControlPlanePreference(key) {
        guard let policy = ChangelogRetentionPolicy.parseStrict(Self.stored(value: value)) else {
          throw StoreError.validation(
            "preference '\(key)' must be 'maximum', 'off', or a positive integer day count")
        }
        try Self.writeAuditRetentionPreference(
          db, service: self, deviceId: deviceId, hlc: hlc, policy: policy,
          operation: SyncNaming.opUpsert, summary: "Set preference '\(key)'")
        return value
      }
      if key == PreferenceKeys.devCalendarAiAccessMode {
        guard let mode = CalendarAiAccessMode.parseStrict(value) else {
          throw StoreError.validation(
            "device_state '\(PreferenceKeys.devCalendarAiAccessMode)' contains invalid value '\(value)'"
          )
        }
        // Skip only when the SAME tier is already explicitly stored. Persist an
        // explicit selection of the current default too, so the user's choice
        // remains stable if the product default ever changes in a later build.
        let storedPrevious = try DeviceStateRepo.readCalendarAiAccessModeIfSet(db)
        guard storedPrevious != mode else {
          return value
        }
        // The purge decision uses the EFFECTIVE previous tier (domain default
        // when unset): moving from a richer effective tier to a reduced one
        // must drop the mirrored detail regardless of whether the previous
        // tier was explicit.
        let effectivePrevious = storedPrevious ?? CalendarAiAccessMode.defaultMode
        if effectivePrevious.reducesDetail(to: mode) {
          try Self.purgeEventKitMirrorForDetailDowngrade(db)
        }
        try DeviceStateRepo.writeCalendarAiAccessMode(db, mode: mode)
        try self.writeChangelogRow(
          db,
          ChangelogEntry(
            operation: SyncNaming.opUpsert, entityType: EntityName.deviceState, entityId: key,
            summary: "Set device state '\(key)'"),
          deviceId: deviceId)
        return value
      }
      guard PreferenceKeys.isKnownPreferenceKey(key) else {
        throw StoreError.validation("unknown preference key '\(key)'")
      }
      if key == PreferenceKeys.prefDefaultListId {
        // Reject a default that does not reference an existing list, so the AI or
        // UI cannot silently store a dangling pointer. (Implicit task creation
        // still heals a default that later becomes dangling to inbox, but storing
        // a bad pointer up front is an error worth surfacing at the write.)
        // Validate the LOGICAL value through the same codec the write uses:
        // callers legitimately pass either the plain list id ("inbox") or the
        // stored JSON form ("\"inbox\"", what export/backup carries), and both
        // encode to the same stored row. Validating the raw argument instead
        // would reject every restored default-list preference.
        let canonical = try Self.canonicalStoredPreferenceValue(key: key, value: value)
        let logicalListId = Self.preferenceString(canonical) ?? value
        try TaskClassification.validateTaskListExists(db, listId: ListId(trusted: logicalListId))
      }
      try Self.writePreference(
        db, service: self, deviceId: deviceId, hlc: hlc, key: key, value: value)
      if key == PreferenceKeys.prefTimezone {
        // A timezone change re-anchors every active task reminder so its stored
        // wall-clock intent ("9 AM") survives the switch, per the schema
        // `original_local_time`/`original_tz` contract. The preference row was
        // just written, so read back the canonical name it resolved to.
        let raw = try String.fetchOne(
          db, sql: "SELECT value FROM preferences WHERE key = ?", arguments: [key])
        if let newTzName = Timezone.parseJsonTimezonePreference(raw),
          let newTz = Timezone.parseTimezoneName(newTzName)
        {
          try Self.rematerializeTaskReminderInstantsForTimezoneChange(
            db, service: self, deviceId: deviceId, hlc: hlc,
            newTzName: newTzName, newTz: newTz)
        }
      }
      return value
    }
  }

  public func deletePreference(key: String) async throws {
    _ = try deletePreferenceWithReceipt(key: key)
  }

  public func deletePreferenceForMcp(key: String) async throws -> McpDeletionReceipt<String> {
    try deletePreferenceWithReceipt(key: key)
  }

  private func deletePreferenceWithReceipt(key: String) throws -> McpDeletionReceipt<String> {
    try withWrite { db, hlc, deviceId in
      if PreferenceKeys.isControlPlanePreference(key) {
        let previous = ChangelogRetentionPolicy.read(db).wireValue
        try Self.writeAuditRetentionPreference(
          db, service: self, deviceId: deviceId, hlc: hlc, policy: .maximum,
          operation: SyncNaming.opDelete, summary: "Deleted preference '\(key)'")
        return McpDeletionReceipt(previous: previous)
      }
      if key == PreferenceKeys.devCalendarAiAccessMode {
        // Deleting the key clears the device-state row, so readers fall back to
        // the domain default (busy_only). When the stored tier was richer than
        // that default, the delete is itself a detail-reducing downgrade, so it
        // must purge the mirror exactly like `setPreference` — otherwise
        // full-detail rows stay at rest under the now-stricter effective tier.
        let previous = try DeviceStateRepo.readCalendarAiAccessMode(db)
        if previous.reducesDetail(to: CalendarAiAccessMode.defaultMode) {
          try Self.purgeEventKitMirrorForDetailDowngrade(db)
        }
        try DeviceStateRepo.clearCalendarAiAccessMode(db)
        try self.writeChangelogRow(
          db,
          ChangelogEntry(
            operation: SyncNaming.opDelete, entityType: EntityName.deviceState, entityId: key,
            summary: "Deleted device state '\(key)'"),
          deviceId: deviceId)
        return McpDeletionReceipt(previous: previous.asString)
      }
      guard PreferenceKeys.isKnownPreferenceKey(key) else {
        throw StoreError.validation("unknown preference key '\(key)'")
      }
      // The configured timezone is the shared calendar-day authority. Removing
      // it would make each peer fall back to its own system zone and immediately
      // split day-scoped identities. Callers may replace it with another valid
      // IANA zone, but cannot delete the authority outright.
      guard key != PreferenceKeys.prefTimezone else {
        throw StoreError.validation(
          "timezone is required for cross-device calendar-day consistency; set another IANA timezone instead"
        )
      }
      let previous = try String.fetchOne(
        db, sql: "SELECT value FROM preferences WHERE key = ?", arguments: [key])
      let preSnapshot = try PayloadLoaders.loadPreferenceDeleteSnapshot(db, key: key)
      let version = hlc.nextVersionString()
      let deleted = try PreferenceRepo.clearPreference(db, key: key, version: version)
      if deleted > 0, let preSnapshot {
        if !PreferenceKeys.isExcludedFromPreferenceEntitySync(key) {
          try self.enqueueDelete(
            db, hlc: hlc, deviceId: deviceId, kind: .preference, entityId: key,
            payload: preSnapshot)
        }
        try self.writeChangelogRow(
          db,
          ChangelogEntry(
            operation: SyncNaming.opDelete, entityType: EntityName.preference, entityId: key,
            summary: "Deleted preference '\(key)'"),
          deviceId: deviceId)
      }
      return McpDeletionReceipt(previous: previous)
    }
  }

  /// Purge the entire device-local EventKit mirror, scrub any saved provider
  /// focus-block label, and disable its provider scope, run atomically with a
  /// detail-reducing calendar-access change (a
  /// `setPreference` downgrade, or a `deletePreference` that falls back to the
  /// stricter default). Previously-mirrored full-detail rows (titles, locations,
  /// descriptions, organizer/attendees, video-call URL) must not survive at rest
  /// under the new, stricter tier: ingest reconciliation only re-redacts the
  /// live ~14-day window, so older browsed windows would otherwise keep verbatim
  /// detail that the timeline / search reads still serve. Same effect as
  /// `clearEventKitMirror()`, inlined here so it commits with the mode write; the
  /// surface's own re-ingest then repopulates only the live window at the new
  /// tier.
  private static func purgeEventKitMirrorForDetailDowngrade(_ db: Database) throws {
    try ProviderRepo.clearProviderEventsByScope(
      db, providerKind: ProviderKind.eventkit, providerScope: eventKitScope)
    // Provider focus-block titles are device-local detail. Their outbound
    // schedule snapshot is already always normalized to "Event", so this local
    // scrub changes no syncable representation and intentionally does not mint
    // a focus-schedule HLC or enqueue an outbox item.
    try db.execute(
      sql: """
        UPDATE focus_schedule_blocks
        SET title = 'Event'
        WHERE event_source = 'provider' AND (title IS NULL OR title <> 'Event')
        """)
    try ProviderRepo.updateProviderScopeState(
      db, providerKind: ProviderKind.eventkit, providerScope: eventKitScope,
      transition: .toggle(enabled: false))
  }

  /// Complete onboarding by writing the setup preferences. Each preference is
  /// an independent LWW-stamped row: `working_hours` / `default_list_id` /
  /// `timezone` plus `setup_completed = true`. When the caller omits timezone,
  /// the current anchored/system IANA zone is materialized explicitly: a
  /// completed setup must never leave peers free to derive different logical
  /// days from their unrelated device zones. Returns the full post-write
  /// preference snapshot.
  public func completeSetup(
    workingHours: String?,
    defaultListID: String?,
    timezone: String?
  ) async throws -> PreferencesSnapshot {
    try withWrite { db, hlc, deviceId in
      if let workingHours, !workingHours.isEmpty {
        try Self.writePreference(
          db, service: self, deviceId: deviceId, hlc: hlc,
          key: PreferenceKeys.prefWorkingHours, value: workingHours)
      }
      if let defaultListID, !defaultListID.isEmpty {
        try TaskClassification.validateTaskListExists(db, listId: ListId(trusted: defaultListID))
        try Self.writePreference(
          db, service: self, deviceId: deviceId, hlc: hlc,
          key: PreferenceKeys.prefDefaultListId, value: defaultListID)
      }
      let requestedTimezone =
        try timezone.trimmedNilIfEmpty ?? WorkflowTimezone.anchoredTimezoneName(db)
      try Self.writePreference(
        db, service: self, deviceId: deviceId, hlc: hlc,
        key: PreferenceKeys.prefTimezone, value: requestedTimezone)
      // Re-read the canonical value written by the shared preference contract.
      // In particular, a caller may surround an otherwise-valid IANA name with
      // whitespace; threading the raw argument into `original_tz` would violate
      // its trimmed schema constraint and roll back setup.
      guard let setupTimezone = try WorkflowTimezone.activeTimezoneName(db),
        let newTz = Timezone.parseTimezoneName(setupTimezone)
      else {
        throw StoreError.invariant("validated setup timezone could not be resolved")
      }
      try Self.rematerializeTaskReminderInstantsForTimezoneChange(
        db, service: self, deviceId: deviceId, hlc: hlc,
        newTzName: setupTimezone, newTz: newTz)
      _ = try Self.writePreferenceRaw(
        db, service: self, deviceId: deviceId, hlc: hlc,
        key: PreferenceKeys.prefSetupCompleted, storedValue: "true")
      return PreferencesSnapshot(values: try Self.readPreferences(db))
    }
  }

  /// Write a preference whose stored value is the canonical-JSON encoding of the
  /// plain `value` (string → JSON string literal; already-valid JSON kept
  /// verbatim), then record the changelog row.
  private static func writePreference(
    _ db: Database,
    service: SwiftLorvexCoreService,
    deviceId: String,
    hlc: HlcSession,
    key: String,
    value: String
  ) throws {
    let storedValue = try canonicalStoredPreferenceValue(key: key, value: value)
    _ = try writePreferenceRaw(
      db, service: service, deviceId: deviceId, hlc: hlc, key: key, storedValue: storedValue)
  }

  /// Write a preference with an already-canonical stored value through the LWW
  /// repo, then record the changelog row.
  private static func writePreferenceRaw(
    _ db: Database,
    service: SwiftLorvexCoreService,
    deviceId: String,
    hlc: HlcSession,
    key: String,
    storedValue: String
  ) throws -> String? {
    guard !PreferenceKeys.isControlPlanePreference(key) else {
      throw StoreError.invariant(
        "control-plane preference '\(key)' cannot be persisted as a preferences row")
    }
    let current = try String.fetchOne(
      db, sql: "SELECT value FROM preferences WHERE key = ?", arguments: [key])
    guard current != storedValue else { return nil }

    let version = hlc.nextVersionString()
    _ = try PreferenceRepo.setPreference(
      db, key: key, value: storedValue, version: version,
      now: SyncTimestampFormat.syncTimestampNow())
    // Device-local preferences (fs paths, per-device sync backend choice) must
    // never cross the sync boundary; only synced keys reach the outbox.
    if !PreferenceKeys.isExcludedFromPreferenceEntitySync(key) {
      try service.enqueueUpsert(
        db, hlc: hlc, deviceId: deviceId, kind: .preference, entityId: key)
    }
    try service.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: SyncNaming.opUpsert, entityType: EntityName.preference, entityId: key,
        summary: "Set preference '\(key)'"),
      deviceId: deviceId)
    return version
  }

  /// Mutate the virtual retention preference directly through its dedicated
  /// control plane. No `preferences` row, `.preference` outbox item, tombstone,
  /// or payload shadow may coexist with that authority.
  private static func writeAuditRetentionPreference(
    _ db: Database,
    service: SwiftLorvexCoreService,
    deviceId: String,
    hlc: HlcSession,
    policy: ChangelogRetentionPolicy,
    operation: String,
    summary: String
  ) throws {
    try AuditRetentionFrontier.enforceControlPlanePreferenceIsolation(db)
    let priorVersion = try AuditRetentionFrontier.currentPolicyVersion(db)
    let version = try VersionFloor.mint(
      hlc: hlc,
      existingVersion: priorVersion.isEmpty ? nil : priorVersion,
      entityType: EntityName.preference,
      entityId: PreferenceKeys.prefAiChangelogRetentionPolicy)
    try AuditRetentionFrontier.adoptPolicyForCurrentScope(
      db, policy: policy, policyVersion: version)
    try AuditRetention.gcChangelog(db)
    try service.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: operation,
        entityType: EntityName.preference,
        entityId: PreferenceKeys.prefAiChangelogRetentionPolicy,
        summary: summary),
      deviceId: deviceId)
  }

  /// If `default_list_id` currently points at `deletedListId`, repoint it to the
  /// always-present `inbox` list as a proper LWW-stamped, changelog'd, synced
  /// preference write, so deleting a list that happens to be the default never
  /// leaves a dangling pointer on this device or its peers. No-op when the
  /// default is unset or points elsewhere; runs inside the caller's transaction.
  static func repointDefaultListAfterDelete(
    _ db: Database, service: SwiftLorvexCoreService, deviceId: String, hlc: HlcSession,
    deletedListId: String
  ) throws {
    let raw = try String.fetchOne(
      db, sql: "SELECT value FROM preferences WHERE key = ?",
      arguments: [PreferenceKeys.prefDefaultListId])
    guard raw == stored(value: deletedListId) else { return }
    try writePreference(
      db, service: service, deviceId: deviceId, hlc: hlc,
      key: PreferenceKeys.prefDefaultListId, value: inboxListId)
  }

  /// Preserve the wall-clock intent of active task reminders across a timezone
  /// preference change: for each open-task reminder whose anchor points at a
  /// different zone, recompute `reminder_at` from `original_local_time` in the
  /// new zone, re-stamp `original_tz`, and enqueue the reminder so peers
  /// converge on the re-anchored instant.
  ///
  /// Reminders without an anchor (rows written before anchoring, or with no
  /// timezone preference set at write time) are left as absolute instants — the
  /// anchor columns are the opt-in signal that a reminder is a wall-clock intent
  /// rather than a fixed moment. A reminder whose re-anchored wall time lands in
  /// the new zone's spring-forward gap is re-anchored to that day's first valid
  /// instant (``ReminderAnchor/rematerializedInstant`` resolves the gap), so its
  /// `original_tz` still advances instead of pinning the stale old-zone instant.
  @discardableResult
  static func rematerializeTaskReminderInstantsForTimezoneChange(
    _ db: Database, service: SwiftLorvexCoreService, deviceId: String, hlc: HlcSession,
    newTzName: String, newTz: TimeZone
  ) throws -> Int {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT tr.id, tr.reminder_at, tr.original_local_time, tr.original_tz, tr.version
        FROM task_reminders tr
        JOIN tasks t ON t.id = tr.task_id
        WHERE tr.cancelled_at IS NULL AND tr.dismissed_at IS NULL
          AND t.status IN (\(StatusName.actionableStatusSqlList)) AND t.archived_at IS NULL
          AND tr.original_local_time IS NOT NULL AND tr.original_tz IS NOT NULL
          AND tr.original_tz <> ?
        """,
      arguments: [newTzName])
    guard !rows.isEmpty else { return 0 }

    var changedReminderIds: [String] = []
    for row in rows {
      let reminderId: String = row[0]
      let reminderAt: String = row[1]
      let originalLocalTime: String = row[2]
      let originalTz: String = row[3]
      let existingVersion: String = row[4]
      guard
        let newInstant = ReminderAnchor.rematerializedInstant(
          currentReminderAtRfc3339: reminderAt, originalLocalTime: originalLocalTime,
          originalTz: originalTz, newTz: newTz)
      else { continue }
      let newReminderAt = SyncTimestampFormat.formatSyncTimestamp(newInstant)
      let version = try VersionFloor.mint(
        hlc: hlc,
        existingVersion: existingVersion,
        entityType: EntityName.taskReminder,
        entityId: reminderId)
      try db.execute(
        sql: """
          UPDATE task_reminders SET reminder_at = ?, original_tz = ?, version = ?
          WHERE id = ? AND version = ?
          """,
        arguments: [newReminderAt, newTzName, version, reminderId, existingVersion])
      guard db.changesCount > 0 else {
        let winner = try String.fetchOne(
          db, sql: "SELECT version FROM task_reminders WHERE id = ?", arguments: [reminderId])
        guard let winner else {
          throw StoreError.notFound(entity: EntityName.taskReminder, id: reminderId)
        }
        throw StoreError.versionSuperseded(
          entityType: EntityName.taskReminder,
          entityId: reminderId,
          attemptedVersion: version,
          existingVersion: winner)
      }
      // Re-anchoring is the same logical one-shot reminder, not a request to
      // notify twice. Preserve a device-local `delivered` receipt. For a
      // still-pending reminder, discard the old OS-arming receipt so the next
      // scheduling pass can arm the newly materialized instant (or surface it
      // as genuinely missed when the new instant is already in the past).
      try db.execute(
        sql: """
          DELETE FROM task_reminder_delivery_state
          WHERE reminder_id = ? AND delivery_state <> 'delivered'
          """,
        arguments: [reminderId])
      changedReminderIds.append(reminderId)
    }
    guard !changedReminderIds.isEmpty else { return 0 }
    try service.enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .taskReminder, entityIds: changedReminderIds)
    return changedReminderIds.count
  }

  /// Restore the cross-device reminder invariant after an inbound page. A
  /// timezone preference and its derived reminder updates are independent
  /// CloudKit records and can arrive in either order or in separate pages; an
  /// offline peer can also author a later reminder using the former zone. Once
  /// the page has reached its final materialized state, normalize every active
  /// anchored reminder to the currently stored product timezone and emit a
  /// strict-successor snapshot for anything that differed.
  @discardableResult
  static func reconcileTaskReminderTimezoneAnchorsAfterInbound(
    _ db: Database, service: SwiftLorvexCoreService, deviceId: String, hlc: HlcSession
  ) throws -> Int {
    guard let timezoneName = try WorkflowTimezone.activeTimezoneName(db) else { return 0 }
    guard let timezone = Timezone.parseTimezoneName(timezoneName) else {
      throw StoreError.invariant("validated timezone preference could not be resolved")
    }
    return try rematerializeTaskReminderInstantsForTimezoneChange(
      db, service: service, deviceId: deviceId, hlc: hlc,
      newTzName: timezoneName, newTz: timezone)
  }

  /// Canonical stored form for a preference value. Already-valid JSON (e.g. a
  /// `working_hours` object, `true`, a number) is kept verbatim; everything else
  /// is treated as a plain string and JSON-encoded to a quoted literal so the
  /// stored column is always valid JSON (matching how `preferenceString`
  /// decodes `"\"inbox\""` → `inbox`).
  static func stored(value: String) -> String {
    if let data = value.data(using: .utf8),
      (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    {
      return value
    }
    if let encoded = try? JSONSerialization.data(
      withJSONObject: value, options: [.fragmentsAllowed]),
      let text = String(data: encoded, encoding: .utf8)
    {
      return text
    }
    return value
  }

  /// Convert the API's plain-or-JSON input into the one canonical stored JSON
  /// node permitted for `key`. This is the local/import counterpart of sync
  /// apply's `PreferenceValueContract` gate.
  static func canonicalStoredPreferenceValue(key: String, value: String) throws -> String {
    let candidate = stored(value: value)
    guard let parsed = JSONValue.parse(candidate) else {
      throw StoreError.validation("preference '\(key)' value is not valid JSON")
    }
    let normalized: JSONValue
    switch PreferenceValueContract.normalize(key: key, value: parsed) {
    case .success(let value): normalized = value
    case .failure(let error): throw StoreError.validation(error.description)
    }
    do {
      return try canonicalizeJSON(normalized)
    } catch {
      throw StoreError.validation("preference '\(key)' value cannot be canonicalized")
    }
  }

  // MARK: - Preference helpers

  /// Read the full `preferences` key/value map as JSON-encoded value strings,
  /// matching `PreferencesSnapshot`'s contract (values carried as the raw
  /// stored JSON text so callers decode per-key shapes themselves).
  static func readPreferences(_ db: Database) throws -> [String: String] {
    let rows = try Row.fetchAll(
      db,
      sql: "SELECT key, value FROM preferences WHERE key <> ?",
      arguments: [PreferenceKeys.prefAiChangelogRetentionPolicy])
    var values: [String: String] = [:]
    for row in rows {
      let key: String = row["key"]
      values[key] = row["value"]
    }
    values[PreferenceKeys.prefAiChangelogRetentionPolicy] =
      ChangelogRetentionPolicy.read(db).wireValue
    return values
  }

  /// Decode a JSON-string preference value (`"\"inbox\""` → `inbox`). Falls
  /// back to the raw text for non-string JSON.
  static func preferenceString(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    if let data = raw.data(using: .utf8),
      let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
      let text = decoded as? String
    {
      return text
    }
    return raw
  }

  static func preferenceBool(_ raw: String?) -> Bool? {
    switch raw {
    case "true": return true
    case "false": return false
    default: return nil
    }
  }

  /// Render the `working_hours` preference (`{"start":"09:00","end":"17:00"}`)
  /// as the `start-end` label `SetupStatusSnapshot` expects.
  static func workingHoursLabel(_ raw: String?) -> String? {
    guard let raw, let data = raw.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let start = object["start"] as? String,
      let end = object["end"] as? String
    else { return nil }
    return "\(start)-\(end)"
  }
}
