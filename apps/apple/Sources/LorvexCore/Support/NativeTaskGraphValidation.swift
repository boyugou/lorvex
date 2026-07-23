import LorvexDomain

struct NativeTaskGraphValidationSummary: Sendable, Equatable {
  let taskIDs: Set<String>
  let requiredListIDs: Set<String>
  let requiredTagIDs: Set<String>
  let maximumHLC: Hlc?
}

enum NativeTaskGraphValidationError: Error, Equatable, CustomStringConvertible {
  case incompatibleSchemaVersion(String)
  case duplicateIdentity(kind: String, identity: String)
  case missingEndpoint(relation: String, identity: String)
  case registerExceedsTaskVersion(taskID: String, register: String)
  case invalidValue(field: String, reason: String)
  case invalidLineage(taskID: String, reason: String)
  case lineageCycle(taskIDs: [String])
  case invalidRollover(taskID: String, reason: String)
  case invalidRelation(relation: String, reason: String)
  case dependencyCycle(taskIDs: [String])
  case terminalHlc(String)

  var description: String {
    switch self {
    case .incompatibleSchemaVersion(let version):
      "native task graph schema version \(version) is unsupported"
    case .duplicateIdentity(let kind, let identity):
      "native task graph repeats \(kind) identity \(identity)"
    case .missingEndpoint(let relation, let identity):
      "native task graph \(relation) references missing endpoint \(identity)"
    case .registerExceedsTaskVersion(let taskID, let register):
      "task \(taskID) has \(register) greater than its row version"
    case .invalidValue(let field, let reason):
      "native task graph has invalid \(field): \(reason)"
    case .invalidLineage(let taskID, let reason):
      "task \(taskID) has invalid recurrence lineage: \(reason)"
    case .lineageCycle(let taskIDs):
      "native task graph recurrence lineage contains a cycle: \(taskIDs.joined(separator: " -> "))"
    case .invalidRollover(let taskID, let reason):
      "task \(taskID) has invalid recurrence rollover: \(reason)"
    case .invalidRelation(let relation, let reason):
      "native task graph has invalid \(relation): \(reason)"
    case .dependencyCycle(let taskIDs):
      "native task graph dependencies contain a cycle involving: \(taskIDs.joined(separator: ", "))"
    case .terminalHlc(let version):
      "native task graph maximum HLC \(version) has no operational successor"
    }
  }
}
