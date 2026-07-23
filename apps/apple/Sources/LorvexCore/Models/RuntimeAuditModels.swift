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

  public init(
    id: String,
    timestamp: String?,
    entityType: String,
    operation: String,
    entityId: String? = nil,
    summary: String,
    initiatedBy: String?,
    mcpTool: String?
  ) {
    self.id = id
    self.timestamp = timestamp
    self.entityType = entityType
    self.operation = operation
    self.entityId = entityId
    self.summary = summary
    self.initiatedBy = initiatedBy
    self.mcpTool = mcpTool
  }
}
