import LorvexDomain

/// Register clocks needed to decide whether a successor is still dominated by
/// a contradictory parent decision or has become an independently edited row.
public struct TaskRolloverRegisterClocks: Sendable, Equatable {
  public let content: String
  public let schedule: String
  public let lifecycle: String
  public let archive: String

  public init(content: String, schedule: String, lifecycle: String, archive: String) {
    self.content = content
    self.schedule = schedule
    self.lifecycle = lifecycle
    self.archive = archive
  }
}

public enum TaskRolloverContradictionResolution: Sendable, Equatable {
  /// The parent decision dominates every child register. Retain the stable row
  /// in a cancelled form so a later authorization can revive the same id.
  case cancelStableSuccessor
  /// At least one child register causally follows the parent decision. Preserve
  /// the user's work by severing lineage and treating the child as a new root.
  case rerootAdvancedSuccessor
}

/// Pure recurrence-chain policy shared by local workflow and sync repair.
public enum TaskRolloverPolicy {
  public static func resolveContradiction(
    decisionVersion: String,
    childClocks: TaskRolloverRegisterClocks
  ) throws -> TaskRolloverContradictionResolution {
    let decision = try parse(decisionVersion, field: "decision_version")
    let child = try [
      ("content_version", childClocks.content),
      ("schedule_version", childClocks.schedule),
      ("lifecycle_version", childClocks.lifecycle),
      ("archive_version", childClocks.archive),
    ].map { field, raw in
      try parse(raw, field: field)
    }
    return child.contains(where: { $0 > decision })
      ? .rerootAdvancedSuccessor
      : .cancelStableSuccessor
  }

  private static func parse(_ raw: String, field: String) throws -> Hlc {
    do {
      return try Hlc.parseCanonical(raw)
    } catch {
      throw StoreError.validation("task rollover \(field) must be a canonical HLC")
    }
  }
}
