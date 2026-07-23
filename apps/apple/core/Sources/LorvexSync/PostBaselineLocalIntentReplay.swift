import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Re-authors one local mutation after an authoritative or future-record
/// baseline has landed, then applies and enqueues the exact resulting state.
enum PostBaselineLocalIntentReplay {
  enum Result {
    /// The queued row carried no user-authored grouped-register mutation.
    /// Dropping it is terminal: replaying its stale full snapshot could
    /// resurrect an entity deleted by the newly adopted baseline.
    case discardedNoRegisterIntent
    case replayed(envelope: SyncEnvelope, outcome: ApplyResult, enqueued: Bool)
  }

  static func applyAndEnqueue(
    _ db: Database, intent: SyncEnvelope,
    registerIntent: EntityRegisterIntent,
    version: Hlc, deviceId: String, registry: EntityApplierRegistry
  ) throws -> Result {
    let registerIntent = try registerIntent.validated(for: intent)
    let isCalendarBaseUpsert =
      intent.entityType == .calendarEvent && intent.operation == .upsert
      && CalendarEventRegisterIntent.isBasePayload(intent.payload)
    let isTaskUpsert = intent.entityType == .task && intent.operation == .upsert
    guard !((isCalendarBaseUpsert || isTaskUpsert) && registerIntent.isEmpty) else {
      return .discardedNoRegisterIntent
    }
    let successor: SyncEnvelope
    switch registerIntent {
    case .calendar(let calendarIntent):
      successor = try calendarBaseSuccessor(
        db, intent: intent, registerIntent: calendarIntent,
        version: version, deviceId: deviceId)
    case .task(let taskIntent):
      successor = try taskSuccessor(
        db, intent: intent, registerIntent: taskIntent,
        version: version, deviceId: deviceId)
    case .none:
      successor = try SyncMutationSemantics.restamp(
        intent, version: version, deviceId: deviceId)
    }
    let outcome = try Apply.applyEnvelope(db, registry: registry, envelope: successor)

    var enqueued = false
    if outcome == .applied {
      if isCalendarBaseUpsert || isTaskUpsert {
        let canonical = try OutboxEnqueue.readEntityPayloadSnapshot(
          db, entityType: successor.entityType.asString, entityId: successor.entityId)
        enqueued = try OutboxEnqueue.enqueuePayloadUpsertReportingInsertion(
          db, entityType: successor.entityType.asString, entityId: successor.entityId,
          payload: canonical,
          context: OutboxWriteContext(
            version: version.description, deviceId: deviceId,
            registerIntent: registerIntent))
      } else {
        enqueued = try Outbox.enqueueCoalesced(db, successor) != nil
      }
    }
    return .replayed(envelope: successor, outcome: outcome, enqueued: enqueued)
  }

  private static func taskSuccessor(
    _ db: Database, intent: SyncEnvelope,
    registerIntent: TaskRegisterIntent,
    version: Hlc, deviceId: String
  ) throws -> SyncEnvelope {
    guard case .object(let local)? = JSONValue.parse(intent.payload) else {
      throw PostBaselineLocalIntentReplayError.invalidTaskPayload(intent.entityId)
    }

    let currentValue: JSONValue?
    do {
      currentValue = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.task, entityId: intent.entityId)
    } catch let error as EnqueueError {
      if case .entityNotFound = error {
        currentValue = nil
      } else {
        throw error
      }
    }

    let current: [String: JSONValue]?
    switch currentValue {
    case .some(.object(let object)):
      current = object
    case .none:
      current = nil
    default:
      throw PostBaselineLocalIntentReplayError.incompatibleTaskIdentity(intent.entityId)
    }

    var replay = current ?? TaskRegisterDescriptor.knownPayload(from: local)
    if registerIntent.contains(.content) {
      copyKeys(TaskRegisterDescriptor.contentFields, from: local, to: &replay)
      replay["content_version"] = .string(version.description)
    }
    if registerIntent.contains(.schedule) {
      copyKeys(TaskRegisterDescriptor.scheduleFields, from: local, to: &replay)
      replay["schedule_version"] = .string(version.description)
    }
    if registerIntent.contains(.lifecycle) {
      copyKeys(TaskRegisterDescriptor.lifecycleFields, from: local, to: &replay)
      replay["lifecycle_version"] = .string(version.description)
    }
    if registerIntent.contains(.archive) {
      copyKeys(TaskRegisterDescriptor.archiveFields, from: local, to: &replay)
      replay["archive_version"] = .string(version.description)
    }
    if current != nil {
      replay["created_at"] = earliestTimestamp(replay["created_at"], local["created_at"])
      replay["updated_at"] = local["updated_at"]
    }
    replay["version"] = .string(version.description)

    let payload = try SyncCanonicalize.canonicalizeJSON(.object(replay))
    return SyncEnvelope(
      entityType: .task, entityId: intent.entityId,
      operation: .upsert, version: version,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: deviceId)
  }

  private static func calendarBaseSuccessor(
    _ db: Database, intent: SyncEnvelope,
    registerIntent: CalendarEventRegisterIntent,
    version: Hlc, deviceId: String
  ) throws -> SyncEnvelope {
    guard case .object(let local)? = JSONValue.parse(intent.payload),
      isBase(local)
    else {
      throw PostBaselineLocalIntentReplayError.invalidCalendarBasePayload(intent.entityId)
    }

    let currentValue: JSONValue?
    do {
      currentValue = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.calendarEvent, entityId: intent.entityId)
    } catch let error as EnqueueError {
      if case .entityNotFound = error {
        currentValue = nil
      } else {
        throw error
      }
    }

    let current: [String: JSONValue]?
    switch currentValue {
    case .some(.object(let object)) where isBase(object):
      current = object
    case .none:
      current = nil
    default:
      throw PostBaselineLocalIntentReplayError.incompatibleCalendarIdentity(intent.entityId)
    }

    // A captured future-schema payload may contain fields this build cannot
    // assign to either independent calendar register. Replay only the fields
    // understood by this runtime. Any retained payload shadow stays attached to
    // the canonical row and the shadow-aware enqueue path below reattaches it to
    // the outbound successor after Apply succeeds.
    var replay = current ?? CalendarEventRegisterDescriptor.knownBasePayload(from: local)
    if registerIntent.contains(.content) {
      copyKeys(CalendarEventRegisterDescriptor.contentFields, from: local, to: &replay)
      replay["content_version"] = .string(version.description)
    }
    if registerIntent.contains(.topology) {
      copyKeys(CalendarEventRegisterDescriptor.topologyFields, from: local, to: &replay)
      replay["recurrence_topology_version"] = .string(version.description)
    }
    if current != nil {
      replay["created_at"] = earliestTimestamp(
        replay["created_at"], local["created_at"])
      if !registerIntent.isEmpty {
        replay["updated_at"] = local["updated_at"]
      }
    }
    replay["version"] = .string(version.description)

    let payload = try SyncCanonicalize.canonicalizeJSON(.object(replay))
    return SyncEnvelope(
      entityType: .calendarEvent, entityId: intent.entityId,
      operation: .upsert, version: version,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: deviceId)
  }

  private static func copyKeys(
    _ keys: [String], from source: [String: JSONValue],
    to destination: inout [String: JSONValue]
  ) {
    for key in keys {
      destination[key] = source[key]
    }
  }

  private static func isBase(_ object: [String: JSONValue]) -> Bool {
    switch object["series_id"] {
    case nil, .some(.null): return true
    default: return false
    }
  }

  private static func earliestTimestamp(
    _ lhs: JSONValue?, _ rhs: JSONValue?
  ) -> JSONValue? {
    guard case .string(let left)? = lhs, case .string(let right)? = rhs else {
      return lhs ?? rhs
    }
    return .string(min(left, right))
  }
}

enum PostBaselineLocalIntentReplayError: Error, Sendable, Equatable {
  case invalidCalendarBasePayload(String)
  case incompatibleCalendarIdentity(String)
  case invalidTaskPayload(String)
  case incompatibleTaskIdentity(String)
}
