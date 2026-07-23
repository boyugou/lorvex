import LorvexDomain

/// Strict version-floor handling for explicit local edits of existing rows.
public enum VersionFloor {
  /// Mint a canonical HLC that strictly dominates `existingVersion`.
  ///
  /// A malformed or non-canonical stored value is corruption and fails closed.
  /// A clock handle unable to dominate the floor returns a typed conflict that
  /// preserves the exact observed version for the top-level detached-lane retry.
  public static func mint(
    hlc: HlcSession,
    existingVersion: String?,
    entityType: String,
    entityId: String
  ) throws -> String {
    guard let existingVersion else {
      return hlc.nextVersionString()
    }

    let floor: Hlc
    do {
      floor = try Hlc.parseCanonical(existingVersion)
    } catch {
      throw StoreError.invariant(
        "\(entityType) '\(entityId)' contains invalid or non-canonical version "
          + "'\(existingVersion)'")
    }
    guard Hlc.hasOperationalWireSuccessor(after: floor) else {
      throw StoreError.versionSuperseded(
        entityType: entityType,
        entityId: entityId,
        attemptedVersion: existingVersion,
        existingVersion: existingVersion)
    }

    let attempted = hlc.nextVersion(dominating: floor).description
    guard let attemptedHlc = try? Hlc.parseCanonical(attempted),
      Hlc.isOperationallyAcceptableWire(attemptedHlc), attemptedHlc > floor
    else {
      throw StoreError.versionSuperseded(
        entityType: entityType,
        entityId: entityId,
        attemptedVersion: attempted,
        existingVersion: existingVersion)
    }
    return attempted
  }
}
