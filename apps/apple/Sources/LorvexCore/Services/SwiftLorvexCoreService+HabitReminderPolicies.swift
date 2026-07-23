import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  public func getAllHabitReminderPolicies() async throws -> [HabitReminderPolicy] {
    try read { db in
      try HabitReminderOps.listAllPolicies(db).map(SwiftLorvexHabitDeserializers.reminderPolicy)
    }
  }

  public func getHabitReminderPolicies(id: LorvexHabit.ID) async throws -> [HabitReminderPolicy] {
    try read { db in try Self.habitReminderPoliciesForDataExport(db, id: id) }
  }

  static func habitReminderPoliciesForDataExport(
    _ db: Database, id: LorvexHabit.ID
  ) throws -> [HabitReminderPolicy] {
    try HabitReminderOps.listPolicies(db, habitId: id)
      .map(SwiftLorvexHabitDeserializers.reminderPolicy)
  }

  public func upsertHabitReminderPolicy(id: LorvexHabit.ID, policy: HabitReminderPolicy)
    async throws
    -> HabitReminderPolicy
  {
    try withWrite { db, hlc, deviceId in
      try self.upsertHabitReminderPolicyInTx(
        db, hlc: hlc, deviceId: deviceId, habitID: id, policy: policy)
    }
  }

  /// Canonical reminder-policy upsert inside the caller's existing transaction.
  /// Shared with habit creation so a new parent and all create-time reminder
  /// slots are one all-or-nothing mutation.
  func upsertHabitReminderPolicyInTx(
    _ db: Database, hlc: HlcSession, deviceId: String,
    habitID: LorvexHabit.ID, policy: HabitReminderPolicy
  ) throws -> HabitReminderPolicy {
    let requestedPolicyId = policy.id.trimmingCharacters(in: .whitespacesAndNewlines)
    let existingVersion =
      requestedPolicyId.isEmpty
      ? nil
      : try String.fetchOne(
        db, sql: "SELECT version FROM habit_reminder_policies WHERE id = ?",
        arguments: [requestedPolicyId])
    let version = try VersionFloor.mint(
      hlc: hlc, existingVersion: existingVersion,
      entityType: EntityName.habitReminderPolicy,
      entityId: requestedPolicyId.isEmpty ? "new" : requestedPolicyId)
    let now = SyncTimestampFormat.syncTimestampNow()
    let row = try HabitReminderOps.upsertHabitReminderPolicy(
      db,
      params: HabitReminderOps.UpsertParams(
        policyId: requestedPolicyId.isEmpty ? nil : requestedPolicyId,
        habitId: habitID,
        reminderTime: policy.reminderTime,
        enabled: policy.enabled,
        version: version,
        now: now))
    try self.enqueueUpsert(
      db, hlc: hlc, deviceId: deviceId, kind: .habitReminderPolicy, entityId: row.id)
    // Stamp the changelog entity_id with the HABIT id (not the policy row id) so
    // `get_ai_changelog?entity_id=<habit>` discovers the policy change under the
    // habit it belongs to. The sync outbox above still targets the policy row.
    try self.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: SyncNaming.opUpsert, entityType: EntityName.habitReminderPolicy,
        entityId: habitID, summary: "Upserted habit reminder policy"),
      deviceId: deviceId)
    return SwiftLorvexHabitDeserializers.reminderPolicy(row)
  }

  public func deleteHabitReminderPolicy(policyID: String) async throws -> HabitReminderPolicy? {
    try withWrite { db, hlc, deviceId in
      guard
        let beforeRow = try HabitReminderOps.listAllPolicies(db).first(where: { $0.id == policyID })
      else { return nil }
      let before = SwiftLorvexHabitDeserializers.reminderPolicy(beforeRow)
      // Capture the tombstone payload before the row disappears; a snapshot
      // failure rolls back the transaction so the delete never outruns sync.
      let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.habitReminderPolicy, entityId: policyID)
      let result = try HabitReminderOps.deleteHabitReminderPolicy(db, policyId: policyID)
      guard result.deleted else { return nil }
      try self.enqueueDelete(
        db, hlc: hlc, deviceId: deviceId, kind: .habitReminderPolicy, entityId: policyID,
        payload: payload)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: SyncNaming.opDelete, entityType: EntityName.habitReminderPolicy,
          entityId: policyID,
          summary: "Deleted habit reminder policy for '\(before.habitName)'"),
        deviceId: deviceId)
      return before
    }
  }
}
