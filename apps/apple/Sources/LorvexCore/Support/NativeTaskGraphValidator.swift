import Foundation

/// Validator dispatch for the graph shape emitted by the current app. Released
/// restore formats use their retained version validator directly through
/// ``NativeTaskGraphRestoreAdapter``; they never inherit future current-version
/// checks by accident.
enum NativeTaskGraphValidator {
  static func validate(
    _ snapshot: NativeTaskGraphSnapshot,
    knownListIDs: Set<String>? = nil,
    knownTagIDs: Set<String>? = nil
  ) throws -> NativeTaskGraphValidationSummary {
    guard snapshot.schemaVersion == NativeTaskGraphSnapshot.currentSchemaVersion else {
      throw NativeTaskGraphValidationError.incompatibleSchemaVersion(snapshot.schemaVersion)
    }
    switch snapshot.schemaVersion {
    case NativeTaskGraphV1Validator.schemaVersion:
      return try NativeTaskGraphV1Validator.validate(
        snapshot, knownListIDs: knownListIDs, knownTagIDs: knownTagIDs)
    default:
      // Advancing `currentSchemaVersion` requires an explicit validator branch.
      throw NativeTaskGraphValidationError.incompatibleSchemaVersion(snapshot.schemaVersion)
    }
  }
}
