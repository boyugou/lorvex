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

  public enum EmissionError: Error, CustomStringConvertible {
    case missingCanonicalVersion(entityType: String, entityId: String)
    case invalidCanonicalVersion(entityType: String, entityId: String, value: String)
    case invalidMintedVersion(entityType: String, entityId: String, value: String)
    case nonDominatingVersion(
      entityType: String, entityId: String, floor: String, minted: String)

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
