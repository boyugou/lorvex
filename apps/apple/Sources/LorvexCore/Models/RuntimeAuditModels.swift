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
