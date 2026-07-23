import Foundation

struct NativeTaskGraphRestorePlan: Sendable {
  let sourceSchemaVersion: String
  let snapshot: NativeTaskGraphSnapshot
  let validation: NativeTaskGraphValidationSummary
}

/// Explicit bridge from retained backup semantics into the app's current graph.
/// Version 1 is an identity adaptation today. When the current graph advances,
/// this is the single mutable bridge that supplies new defaults/transforms while
/// the frozen v1 validator continues to define what old backups mean.
enum NativeTaskGraphRestoreAdapter {
  static func prepare(
    _ snapshot: NativeTaskGraphSnapshot,
    knownListIDs: Set<String>? = nil,
    knownTagIDs: Set<String>? = nil
  ) throws -> NativeTaskGraphRestorePlan {
    switch snapshot.schemaVersion {
    case NativeTaskGraphV1Validator.schemaVersion:
      return try prepareVersion1(
        snapshot, knownListIDs: knownListIDs, knownTagIDs: knownTagIDs)
    default:
      throw NativeTaskGraphValidationError.incompatibleSchemaVersion(snapshot.schemaVersion)
    }
  }

  static func prepareVersion1(
    _ snapshot: NativeTaskGraphSnapshot,
    knownListIDs: Set<String>? = nil,
    knownTagIDs: Set<String>? = nil
  ) throws -> NativeTaskGraphRestorePlan {
    let validation = try NativeTaskGraphV1Validator.validate(
      snapshot, knownListIDs: knownListIDs, knownTagIDs: knownTagIDs)
    let adapted = adaptVersion1ToCurrent(snapshot)
    return NativeTaskGraphRestorePlan(
      sourceSchemaVersion: NativeTaskGraphV1Validator.schemaVersion,
      snapshot: adapted,
      validation: validation)
  }

  private static func adaptVersion1ToCurrent(
    _ snapshot: NativeTaskGraphSnapshot
  ) -> NativeTaskGraphSnapshot {
    // Schema 1 is also the current graph today, so this is the identity. Keep
    // the explicit copy boundary: future current-only fields/defaults belong
    // here, not in the frozen wire or the version-1 validator.
    snapshot
  }
}
