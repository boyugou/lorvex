/// Final cross-category closure check for an assembled human archive.
///
/// Task roots and list/tag categories are loaded by separate service calls. A
/// concurrent root mutation can therefore make each individual read valid but
/// leave the final archive internally open. Only categories selected into the
/// archive are checked: a task-only archive deliberately remains portable and
/// may fall back during import instead of claiming exact restore closure.
enum NativeTaskGraphArchiveClosureValidator {
  static func validate(
    _ snapshot: NativeTaskGraphSnapshot,
    exportedListIDs: Set<String>?,
    exportedTagIDs: Set<String>?
  ) throws {
    let summary = try NativeTaskGraphValidator.validate(snapshot)
    if let exportedListIDs,
      !summary.requiredListIDs.isSubset(of: exportedListIDs)
    {
      let missing = summary.requiredListIDs.subtracting(exportedListIDs).sorted()
      throw NativeTaskGraphValidationError.missingEndpoint(
        relation: "exported list category", identity: missing.joined(separator: ","))
    }
    if let exportedTagIDs,
      !summary.requiredTagIDs.isSubset(of: exportedTagIDs)
    {
      let missing = summary.requiredTagIDs.subtracting(exportedTagIDs).sorted()
      throw NativeTaskGraphValidationError.missingEndpoint(
        relation: "exported tag category", identity: missing.joined(separator: ","))
    }
  }
}
