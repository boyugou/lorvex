import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Per-entity apply handlers for the day-scoped aggregates, whose natural
/// primary key is a `date` string: `daily_briefing` (a single row) and
/// `daily_review` (with the `daily_review_task_links` /
/// `daily_review_list_links` materialization child tables).
///
/// Each upsert runs the sync-mode upsert (the envelope is authoritative for
/// `timezone` / `created_at`). A daily review rebuilds its embedded child rows
/// atomically — but only when the parent row was actually written (the LWW gate
/// accepted). The child rows have no `version` column, no outbox enqueue site,
/// and no dispatch entry: their state is wholly derived from the parent payload
/// and rebuilt on every apply, so the parent delete cascades them via FK WITHOUT
/// per-edge tombstones (no peer can resurrect a stale edge). Each delete carries
/// a defense-in-depth LWW gate via ``ApplyLww/lwwGatedDelete``.
enum ApplyDayScoped {

  /// A present `null` maps to an empty array (an explicit clear); a present array
  /// maps to its string list. A non-array, or an array with a non-string element,
  /// errors. Callers apply absence-preserving semantics by gating on key presence
  /// BEFORE calling (an ABSENT key preserves the existing children upstream), so
  /// in practice only present values reach here; the absent arm is a defensive
  /// fallback that maps to the empty array.
  private static func stringArrayField(_ obj: [String: JSONValue], _ key: String) throws
    -> [String]
  {
    switch obj[key] {
    case .none, .null:
      return []
    case .array(let items):
      return try items.map { entry in
        guard case .string(let s) = entry else {
          throw ApplyError.invalidPayload(
            "invalid day-scoped payload: \(key) must contain only strings")
        }
        return s
      }
    default:
      throw ApplyError.invalidPayload(
        "invalid day-scoped payload: \(key) must be an array of strings")
    }
  }

  /// Validate embedded storage identities with the same canonical rules as a
  /// top-level sync envelope. Day-scoped children are soft references, so SQL
  /// foreign keys cannot protect this boundary from malformed peer values.
  private static func validatedEntityIdArray(
    _ obj: [String: JSONValue], key: String, entity: String, kind: EntityKind
  ) throws -> [String] {
    let values = try stringArrayField(obj, key)
    for (index, value) in values.enumerated() {
      guard case .success = SyncEntityId.validateForKind(kind, value) else {
        throw ApplyError.invalidPayload(
          "invalid \(entity) payload: \(key)[\(index)] has a non-canonical identity")
      }
    }
    return values
  }

  // MARK: - daily_briefing

  static func applyDailyBriefingUpsert(
    _ db: Database, entityId: String, payload: String, version: String, tieBreak: LwwTieBreak
  ) throws {
    let val = try ApplyJSON.parseObject(payload)
    let briefing = ApplyAggregate.scrub(
      try ApplyJSON.requiredStr(val, "briefing", entity: "daily_briefing"))
    // A blank briefing would trip the table CHECK as a batch-fatal constraint
    // error; drop the one bad envelope instead.
    guard !briefing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ApplyError.invalidPayload("daily_briefing \(entityId) briefing must not be blank")
    }
    let timezone = try ApplyJSON.optionalStr(val, "timezone", entity: "daily_briefing")
    let createdAt = try ApplyJSON.requiredStr(val, "created_at", entity: "daily_briefing")
    let updatedAt = try ApplyJSON.requiredStr(val, "updated_at", entity: "daily_briefing")
    do {
      _ = try DailyBriefingRepo.syncUpsertBriefing(
        db, date: entityId, briefing: briefing,
        timezone: timezone, version: version, createdAt: createdAt, updatedAt: updatedAt,
        versionCmp: tieBreak.sqlOp)
    } catch { throw ApplyError.lift(error) }
  }

  static func applyDailyBriefingDelete(_ db: Database, entityId: String, version: String) throws {
    try ApplyLww.lwwGatedDelete(
      db, table: "daily_briefings", pkColumns: ["date"], pkValues: [entityId],
      incomingVersion: version)
  }

  // MARK: - daily_review

  static func applyDailyReviewUpsert(
    _ db: Database, entityId: String, payload: String, version: String, tieBreak: LwwTieBreak
  ) throws {
    let val = try ApplyJSON.parseObject(payload)
    let date = entityId
    let summary = try ApplyJSON.requiredStr(val, "summary", entity: "daily_review")
    let mood = try ApplyJSON.optionalInt64(val, "mood", entity: "daily_review")
    let energyLevel = try ApplyJSON.optionalInt64(val, "energy_level", entity: "daily_review")
    // Validate the 1…5 scale at the trust boundary before the SQL bind. An
    // out-of-range value would trip `CHECK (mood/energy_level BETWEEN 1 AND 5)`
    // as a deterministic SQLITE_CONSTRAINT that `applyInbound` treats as
    // batch-fatal, wedging inbound sync; drop the one bad envelope instead.
    try validateDayReviewScale(mood, field: "mood", entityId: date)
    try validateDayReviewScale(energyLevel, field: "energy_level", entityId: date)
    let wins = try ApplyJSON.optionalStr(val, "wins", entity: "daily_review")
    let blockers = try ApplyJSON.optionalStr(val, "blockers", entity: "daily_review")
    let learnings = try ApplyJSON.optionalStr(val, "learnings", entity: "daily_review")
    let timezone = try ApplyJSON.optionalStr(val, "timezone", entity: "daily_review")
    let createdAt = try ApplyJSON.requiredStr(val, "created_at", entity: "daily_review")
    let updatedAt = try ApplyJSON.requiredStr(val, "updated_at", entity: "daily_review")

    let wrote: Bool
    do {
      wrote = try DailyReviewOpsRepo.syncUpsertDailyReview(
        db, date: date, summary: summary, mood: mood, energyLevel: energyLevel, wins: wins,
        blockers: blockers, learnings: learnings, timezone: timezone,
        version: version, createdAt: createdAt, updatedAt: updatedAt, versionCmp: tieBreak.sqlOp)
    } catch { throw ApplyError.lift(error) }

    // Absence-preserving (SYNC-MED-2): rebuild each link collection only when the
    // envelope carried its explicit key (an array, including empty). An absent key
    // preserves the existing links rather than wiping them.
    if wrote {
      if val["linked_task_ids"] != nil {
        let taskIds = try validatedEntityIdArray(
          val, key: "linked_task_ids", entity: "daily_review", kind: .task)
        do {
          try DailyReviewOpsRepo.materializeReviewTaskLinks(db, date: date, taskIds: taskIds)
        } catch { throw ApplyError.lift(error) }
      }
      if val["linked_list_ids"] != nil {
        let listIds = try validatedEntityIdArray(
          val, key: "linked_list_ids", entity: "daily_review", kind: .list)
        do {
          try DailyReviewOpsRepo.materializeReviewListLinks(db, date: date, listIds: listIds)
        } catch { throw ApplyError.lift(error) }
      }
    }
  }

  static func applyDailyReviewDelete(_ db: Database, entityId: String, version: String) throws {
    try ApplyLww.lwwGatedDelete(
      db, table: "daily_reviews", pkColumns: ["date"], pkValues: [entityId],
      incomingVersion: version)
  }

  /// Reject a `daily_review` `mood` / `energy_level` outside the schema's 1…5
  /// scale (NULL passes) at the trust boundary, so a crafted out-of-range value
  /// drops as ``ApplyError/invalidPayload(_:)`` instead of tripping the SQL CHECK
  /// and aborting the whole inbound batch.
  private static func validateDayReviewScale(
    _ value: Int64?, field: String, entityId: String
  ) throws {
    guard let value else { return }
    if !(ValidationLimits.moodMin...ValidationLimits.moodMax).contains(value) {
      throw ApplyError.invalidPayload(
        "daily_review \(entityId) \(field) must be between \(ValidationLimits.moodMin) and "
          + "\(ValidationLimits.moodMax) or null (got \(value))")
    }
  }
}

// MARK: - EntityApplier conformances

public struct DailyBriefingApplier: EntityApplier {
  public init() {}
  public var handledEntityTypes: [String] { [EntityName.dailyBriefing] }
  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    try ApplyDayScoped.applyDailyBriefingUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, tieBreak: tieBreak)
    return .applied
  }
  public func applyDelete(_ db: Database, envelope: SyncEnvelope, applyTs: String) throws
    -> EntityApplyOutcome
  {
    try ApplyDayScoped.applyDailyBriefingDelete(
      db, entityId: envelope.entityId, version: envelope.version.description)
    return .applied
  }
}

public struct DailyReviewApplier: EntityApplier {
  public init() {}
  public var handledEntityTypes: [String] { [EntityName.dailyReview] }
  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    try ApplyDayScoped.applyDailyReviewUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, tieBreak: tieBreak)
    return .applied
  }
  public func applyDelete(_ db: Database, envelope: SyncEnvelope, applyTs: String) throws
    -> EntityApplyOutcome
  {
    try ApplyDayScoped.applyDailyReviewDelete(
      db, entityId: envelope.entityId, version: envelope.version.description)
    return .applied
  }
}
