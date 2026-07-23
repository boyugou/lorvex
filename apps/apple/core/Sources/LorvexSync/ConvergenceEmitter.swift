import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// One fail-closed path for snapshots that must be re-emitted to make peers
/// converge after a merge, fallback, or trigger-authored re-home.
public enum ConvergenceEmitter {
  public enum Outcome: Sendable, Equatable {
    case enqueued
    /// The target was concurrently removed. Re-emitting it would resurrect data,
    /// so absence is the one benign reason not to enqueue a convergence snapshot.
    case targetGone
  }

  /// The exact canonical state re-established after CloudKit physically
  /// removed an identity that must remain represented remotely. A live row is
  /// re-authored at a strict successor; a terminal tombstone is re-enqueued at
  /// its original death HLC so recovery never resurrects the entity.
  public enum CanonicalStateOutcome: Sendable, Equatable {
    case enqueuedUpsert
    case enqueuedDelete
    case alreadyPendingDelete
  }

  public enum EmissionError: Error, CustomStringConvertible {
    case missingCanonicalVersion(entityType: String, entityId: String)
    case invalidCanonicalVersion(entityType: String, entityId: String, value: String)
    case invalidMintedVersion(entityType: String, entityId: String, value: String)
    case nonDominatingVersion(
      entityType: String, entityId: String, floor: String, minted: String)
    case missingCanonicalState(entityType: String, entityId: String)
    case deleteReassertionNotEligible(
      entityType: String, entityId: String, version: String)

    public var description: String {
      switch self {
      case .missingCanonicalVersion(let type, let id):
        return "convergence target has no canonical version: \(type)/\(id)"
      case .invalidCanonicalVersion(let type, let id, let value):
        return "convergence target has invalid version \(value): \(type)/\(id)"
      case .invalidMintedVersion(let type, let id, let value):
        return "convergence minter returned invalid version \(value): \(type)/\(id)"
      case .nonDominatingVersion(let type, let id, let floor, let minted):
        return "convergence version \(minted) does not dominate \(floor): \(type)/\(id)"
      case .missingCanonicalState(let type, let id):
        return "convergence target has neither a live row nor a tombstone: \(type)/\(id)"
      case .deleteReassertionNotEligible(let type, let id, let version):
        return "convergence delete at \(version) is not eligible for upload: \(type)/\(id)"
      }
    }
  }

  /// Read the target's current canonical snapshot, derive its exact HLC floor,
  /// mint and validate a strict successor, then enqueue that same snapshot.
  /// Every convergence caller uses this rather than guessing a floor from the
  /// triggering envelope (which may be older than the merged target row).
  @discardableResult
  public static func enqueueCurrentSnapshot(
    _ db: Database,
    entityType: String,
    entityId: String,
    mintVersion: (Hlc?) -> String,
    deviceId: String
  ) throws -> Outcome {
    let payload: JSONValue
    do {
      payload = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: entityType, entityId: entityId)
    } catch EnqueueError.entityNotFound {
      return .targetGone
    }

    try enqueueSnapshot(
      db, entityType: entityType, entityId: entityId, payload: payload,
      mintVersion: mintVersion, deviceId: deviceId)
    return .enqueued
  }

  /// Strict physical-deletion recovery for a canonical identity. The two legal
  /// endpoints are deliberately distinguished before any death metadata is
  /// changed:
  ///
  /// - a live row proves that any same-identity tombstone is contradictory, so
  ///   the tombstone is removed and the current snapshot is re-authored;
  /// - an absent row with a tombstone remains deleted, so an eligible Delete is
  ///   rebuilt at the stored death HLC without removing or advancing the
  ///   tombstone;
  /// - absence of both states is an invariant failure and aborts the containing
  ///   inbound page transaction.
  @discardableResult
  public static func enqueueCurrentCanonicalState(
    _ db: Database,
    entityType: String,
    entityId: String,
    mintVersion: (Hlc?) -> String,
    deviceId: String
  ) throws -> CanonicalStateOutcome {
    let payload: JSONValue?
    do {
      payload = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: entityType, entityId: entityId)
    } catch EnqueueError.entityNotFound {
      payload = nil
    }

    if let payload {
      // The live snapshot was established first, inside the same writer
      // transaction. Only now is it safe to classify the tombstone as stale.
      _ = try Tombstone.removeTombstone(
        db, entityType: entityType, entityId: entityId)
      try enqueueSnapshot(
        db, entityType: entityType, entityId: entityId, payload: payload,
        mintVersion: mintVersion, deviceId: deviceId)
      return .enqueuedUpsert
    }

    guard
      let tombstone = try Tombstone.getTombstone(
        db, entityType: entityType, entityId: entityId)
    else {
      throw EmissionError.missingCanonicalState(
        entityType: entityType, entityId: entityId)
    }

    let emitted = try OutboxEnqueue.enqueuePayloadDeleteReportingInsertion(
      db, entityType: entityType, entityId: entityId, payload: .object([:]),
      context: OutboxWriteContext(
        version: tombstone.version, deviceId: deviceId))
    if emitted { return .enqueuedDelete }

    // Equal-version coalescing is a valid idempotent result only when the exact
    // canonical Delete is already transport-eligible. Never accept a newer row,
    // retry fence, or malformed payload as satisfying this recovery obligation.
    let expectedPayload = try SyncCanonicalize.canonicalizeJSON(
      .object(["version": .string(tombstone.version)]))
    let alreadyReady = try Bool.fetchOne(
      db,
      sql: """
        SELECT EXISTS(
          SELECT 1 FROM sync_outbox
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            AND operation = ? AND version = ?
            AND payload_schema_version = ? AND payload = ?
            AND disposition IS NULL AND retry_count < ?
        )
        """,
      arguments: [
        entityType, entityId, SyncNaming.opDelete, tombstone.version,
        LorvexVersion.payloadSchemaVersion, expectedPayload, Outbox.maxRetries,
      ]) ?? false
    guard alreadyReady else {
      throw EmissionError.deleteReassertionNotEligible(
        entityType: entityType, entityId: entityId, version: tombstone.version)
    }
    return .alreadyPendingDelete
  }

  private static func enqueueSnapshot(
    _ db: Database,
    entityType: String,
    entityId: String,
    payload: JSONValue,
    mintVersion: (Hlc?) -> String,
    deviceId: String
  ) throws {

    guard case .object(let object) = payload else {
      throw EmissionError.missingCanonicalVersion(
        entityType: entityType, entityId: entityId)
    }
    let rawFloor: String
    if case .string(let payloadVersion)? = object["version"] {
      rawFloor = payloadVersion
    } else if entityType == EntityName.preference,
      let storedVersion = try String.fetchOne(
        db, sql: "SELECT version FROM preferences WHERE key = ?",
        arguments: [entityId])
    {
      // Preference upsert snapshots intentionally omit `version`; the outbox
      // writer injects it. A physical-deletion reassertion still needs the live
      // row's exact HLC as its minting floor, so read that one canonical column
      // without changing the preference wire shape.
      rawFloor = storedVersion
    } else {
      throw EmissionError.missingCanonicalVersion(
        entityType: entityType, entityId: entityId)
    }
    let floor: Hlc
    do {
      floor = try Hlc.parseCanonical(rawFloor)
      guard floor.description == rawFloor else { throw HlcParseSentinel.nonCanonical }
    } catch {
      throw EmissionError.invalidCanonicalVersion(
        entityType: entityType, entityId: entityId, value: rawFloor)
    }

    let rawMinted = mintVersion(floor)
    let minted: Hlc
    do {
      minted = try Hlc.parseCanonical(rawMinted)
      guard minted.description == rawMinted else { throw HlcParseSentinel.nonCanonical }
    } catch {
      throw EmissionError.invalidMintedVersion(
        entityType: entityType, entityId: entityId, value: rawMinted)
    }
    guard minted > floor else {
      throw EmissionError.nonDominatingVersion(
        entityType: entityType, entityId: entityId,
        floor: floor.description, minted: minted.description)
    }

    try OutboxEnqueue.enqueuePayloadUpsert(
      db, entityType: entityType, entityId: entityId, payload: payload,
      context: OutboxWriteContext(version: minted.description, deviceId: deviceId))
  }

  private enum HlcParseSentinel: Error { case nonCanonical }
}
