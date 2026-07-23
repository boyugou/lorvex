import Foundation
import GRDB
import LorvexDomain
import LorvexStore

extension AuditRetentionFrontier {
  static func normalizeCloudUnseenAuditRows(
    _ db: Database, accountIdentifier: String?, epoch: Int64
  ) throws {
    try validateEpoch(epoch)
    let scopePredicate: String
    let outboxArguments: StatementArguments
    let updateArguments: StatementArguments
    if let accountIdentifier {
      try validateAccountIdentifier(accountIdentifier)
      scopePredicate =
        "(audit.retention_account_identifier IS NULL OR audit.retention_account_identifier = ?)"
      outboxArguments = [
        EntityName.aiChangelog, SyncNaming.opUpsert, accountIdentifier,
        SyncNaming.localAuditCoalescedDeleteDropped,
      ]
      updateArguments = [
        accountIdentifier, epoch, accountIdentifier,
        SyncNaming.localAuditCoalescedDeleteDropped,
      ]
    } else {
      scopePredicate = "audit.retention_account_identifier IS NULL"
      outboxArguments = [
        EntityName.aiChangelog, SyncNaming.opUpsert,
        SyncNaming.localAuditCoalescedDeleteDropped,
      ]
      updateArguments = [
        accountIdentifier, epoch, SyncNaming.localAuditCoalescedDeleteDropped,
      ]
    }

    // Select every matching pending upload in one indexed join rather than
    // issuing one presence probe and one outbox scan per canonical audit row.
    let outboxes = try Row.fetchAll(
      db,
      sql: """
        SELECT outbox.id, outbox.payload
        FROM sync_outbox outbox
        JOIN ai_changelog audit ON audit.id = outbox.entity_id
        WHERE outbox.entity_type = ? AND outbox.operation = ?
          AND outbox.synced_at IS NULL
          AND \(scopePredicate)
          AND audit.operation != ?
          AND NOT EXISTS (
            SELECT 1 FROM audit_changelog_cloud_presence presence
            WHERE presence.entity_id = audit.id
          )
        ORDER BY outbox.id ASC
        """,
      arguments: outboxArguments)
    for outbox in outboxes {
      guard case .object(var object)? = JSONValue.parse(outbox["payload"] as String) else {
        throw AuditRetentionStateError.invalidOutboundAuditRow(outbox["id"])
      }
      object["retention_epoch"] = .int(epoch)
      let canonical = try SyncCanonicalize.canonicalizeJSON(.object(object))
      try db.execute(
        sql: "UPDATE sync_outbox SET payload = ? WHERE id = ?",
        arguments: [canonical, outbox["id"] as Int64])
    }

    // Normalize the full eligible set with one guarded statement. The same
    // presence predicate protects rows whose cloud history makes rewriting
    // their account/epoch identity unsafe.
    try db.execute(
      sql: """
        UPDATE ai_changelog AS audit
        SET retention_account_identifier = ?, retention_epoch = ?
        WHERE \(scopePredicate)
          AND audit.operation != ?
          AND NOT EXISTS (
            SELECT 1 FROM audit_changelog_cloud_presence presence
            WHERE presence.entity_id = audit.id
          )
        """,
      arguments: updateArguments)
  }

  static func dropAuditPendingInbox(_ db: Database) throws {
    // Pending records lack an account column; on an explicit account switch
    // or same-account zone-generation switch they belong to the context being
    // left and cannot be interpreted in the newly active zone.
    try db.execute(
      sql: "DELETE FROM sync_pending_inbox WHERE envelope_entity_type = ?",
      arguments: [EntityName.aiChangelog])
  }
}
