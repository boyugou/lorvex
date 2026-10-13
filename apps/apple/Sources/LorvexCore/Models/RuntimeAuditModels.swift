import LorvexDomain
public struct AIChangelogSnapshot: Equatable, Sendable {
  public var entries: [AIChangelogEntry]
  public var truncated: Bool
  public var nextOffset: Int?

  public init(entries: [AIChangelogEntry], truncated: Bool, nextOffset: Int?) {
    self.entries = entries
    self.truncated = truncated
    self.nextOffset = nextOffset
  }
}

public struct AIChangelogEntry: Identifiable, Equatable, Sendable {
  public var id: String
  public var timestamp: String?
  public var entityType: String
  public var operation: String
  public var entityId: String?
  public var summary: String
  public var initiatedBy: String?
  public var mcpTool: String?
  /// True when the row recorded the entity as it was before the change.
  public var hasBefore: Bool
  /// True when the row recorded the entity as it was after the change.
  public var hasAfter: Bool
  /// The current title of the task the row is about; nil for other entity
  /// kinds, a batch, or a task that no longer exists.
  public var entityTitle: String?

  public init(
    id: String,
    timestamp: String?,
    entityType: String,
    operation: String,
    entityId: String? = nil,
    summary: String,
    initiatedBy: String?,
    mcpTool: String?,
    hasBefore: Bool = false,
    hasAfter: Bool = false,
    entityTitle: String? = nil
  ) {
    self.id = id
    self.timestamp = timestamp
    self.entityType = entityType
    self.operation = operation
    self.entityId = entityId
    self.summary = summary
    self.initiatedBy = initiatedBy
    self.mcpTool = mcpTool
    self.hasBefore = hasBefore
    self.hasAfter = hasAfter
    self.entityTitle = entityTitle
  }
}

/// What undoing an assistant's update to a task did: the task as it is now, the fields that went
/// back to what they were before the change, and the fields left as they are because they changed
/// again after it (a person's or another assistant's later edit is never overwritten).
public struct UndoAIChangeResult: Equatable, Sendable {
  public var task: LorvexTask
  /// Wire names of the fields restored to their earlier value.
  public var reverted: [String]
  /// Wire names of the fields the change touched that hold something else now.
  public var kept: [String]

  public init(task: LorvexTask, reverted: [String], kept: [String]) {
    self.task = task
    self.reverted = reverted
    self.kept = kept
  }
}
