import Foundation
import LorvexDomain

/// Device-local provenance describing which independent task registers a
/// queued task Upsert actually changed.
public struct TaskRegisterIntent: OptionSet, Sendable, Equatable, Hashable {
  public let rawValue: Int64

  public init(rawValue: Int64) {
    self.rawValue = rawValue
  }

  public static let content = TaskRegisterIntent(rawValue: 1 << 0)
  public static let schedule = TaskRegisterIntent(rawValue: 1 << 1)
  public static let lifecycle = TaskRegisterIntent(rawValue: 1 << 2)
  public static let archive = TaskRegisterIntent(rawValue: 1 << 3)
  public static let all: TaskRegisterIntent = [.content, .schedule, .lifecycle, .archive]

  /// Infer authored registers for a single-stamp task snapshot, such as create
  /// or full-snapshot fallback. A business mutation that advances multiple
  /// registers through separate HLCs must pass their explicit union instead;
  /// final-row inference cannot reconstruct earlier stamps.
  public static func inferredLocalMutation(from payload: JSONValue) -> Self {
    guard case .object(let object) = payload,
      case .string(let rowVersion)? = object["version"]
    else { return [] }

    var result: Self = []
    if case .string(rowVersion)? = object["content_version"] {
      result.insert(.content)
    }
    if case .string(rowVersion)? = object["schedule_version"] {
      result.insert(.schedule)
    }
    if case .string(rowVersion)? = object["lifecycle_version"] {
      result.insert(.lifecycle)
    }
    if case .string(rowVersion)? = object["archive_version"] {
      result.insert(.archive)
    }
    return result
  }

  /// Derive the exact authored-register set from two canonical task snapshots.
  /// A value-group change without a matching clock change is a writer bug and
  /// fails closed instead of queuing provenance that the grouped merge cannot
  /// honor.
  public static func authoredRegisters(
    between before: JSONValue, and after: JSONValue
  ) throws -> Self {
    guard case .object(let lhs) = before, case .object(let rhs) = after else {
      throw TaskRegisterIntentError.invalidTaskSnapshot
    }

    var result: Self = []
    try collectAuthoredRegister(
      .content, clock: "content_version", fields: TaskRegisterDescriptor.contentFields,
      lhs: lhs, rhs: rhs, result: &result)
    try collectAuthoredRegister(
      .schedule, clock: "schedule_version", fields: TaskRegisterDescriptor.scheduleFields,
      lhs: lhs, rhs: rhs, result: &result)
    try collectAuthoredRegister(
      .lifecycle, clock: "lifecycle_version", fields: TaskRegisterDescriptor.lifecycleFields,
      lhs: lhs, rhs: rhs, result: &result)
    try collectAuthoredRegister(
      .archive, clock: "archive_version", fields: TaskRegisterDescriptor.archiveFields,
      lhs: lhs, rhs: rhs, result: &result)
    return result
  }

  /// Retain only provenance whose authored register is byte-identical in the
  /// replacement payload. Coalescing can replace some registers with remote
  /// convergence winners while preserving another local register unchanged.
  func retainingUnchangedRegisters(
    existingPayload: String, replacementPayload: String
  ) -> Self {
    guard !isEmpty,
      case .object(let existing)? = JSONValue.parse(existingPayload),
      case .object(let replacement)? = JSONValue.parse(replacementPayload)
    else { return [] }

    var retained: Self = []
    if contains(.content),
      TaskRegisterDescriptor.snapshotsMatch(
        keys: TaskRegisterDescriptor.contentSnapshotKeys,
        lhs: existing, rhs: replacement)
    {
      retained.insert(.content)
    }
    if contains(.schedule),
      TaskRegisterDescriptor.snapshotsMatch(
        keys: TaskRegisterDescriptor.scheduleSnapshotKeys,
        lhs: existing, rhs: replacement)
    {
      retained.insert(.schedule)
    }
    if contains(.lifecycle),
      TaskRegisterDescriptor.snapshotsMatch(
        keys: TaskRegisterDescriptor.lifecycleSnapshotKeys,
        lhs: existing, rhs: replacement)
    {
      retained.insert(.lifecycle)
    }
    if contains(.archive),
      TaskRegisterDescriptor.snapshotsMatch(
        keys: TaskRegisterDescriptor.archiveSnapshotKeys,
        lhs: existing, rhs: replacement)
    {
      retained.insert(.archive)
    }
    return retained
  }

  private static func collectAuthoredRegister(
    _ register: Self,
    clock: String,
    fields: [String],
    lhs: [String: JSONValue],
    rhs: [String: JSONValue],
    result: inout Self
  ) throws {
    guard let oldClock = lhs[clock], let newClock = rhs[clock] else {
      throw TaskRegisterIntentError.missingClock(clock)
    }
    let valuesChanged = !TaskRegisterDescriptor.snapshotsMatch(
      keys: fields, lhs: lhs, rhs: rhs)
    let clockChanged = oldClock != newClock
    if valuesChanged && !clockChanged {
      throw TaskRegisterIntentError.unstampedRegister(clock)
    }
    if clockChanged {
      result.formUnion(register)
    }
  }
}

enum TaskRegisterIntentError: Error, Sendable, Equatable {
  case invalidTaskSnapshot
  case missingClock(String)
  case unstampedRegister(String)
}
