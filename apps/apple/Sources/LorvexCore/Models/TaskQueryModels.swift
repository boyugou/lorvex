public struct TaskSearchResult: Equatable, Sendable {
  public var query: String
  public var tasks: [LorvexTask]
  public var totalMatching: Int
  public var returned: Int
  public var limit: Int
  public var offset: Int
  public var nextOffset: Int?
  public var truncated: Bool

  public init(
    query: String,
    tasks: [LorvexTask],
    totalMatching: Int,
    returned: Int,
    limit: Int,
    offset: Int,
    nextOffset: Int?,
    truncated: Bool
  ) {
    self.query = query
    self.tasks = tasks
    self.totalMatching = totalMatching
    self.returned = returned
    self.limit = limit
    self.offset = offset
    self.nextOffset = nextOffset
    self.truncated = truncated
  }
}

public struct TaskPageResult: Equatable, Sendable {
  public var tasks: [LorvexTask]
  public var totalMatching: Int
  public var returned: Int
  public var limit: Int
  public var offset: Int
  public var nextOffset: Int?
  public var truncated: Bool

  public init(
    tasks: [LorvexTask],
    totalMatching: Int,
    returned: Int,
    limit: Int,
    offset: Int,
    nextOffset: Int?,
    truncated: Bool
  ) {
    self.tasks = tasks
    self.totalMatching = totalMatching
    self.returned = returned
    self.limit = limit
    self.offset = offset
    self.nextOffset = nextOffset
    self.truncated = truncated
  }
}

public struct TaskListQueryRequest: Equatable, Sendable {
  public var status: String
  public var listID: LorvexList.ID?
  public var priority: Int?
  public var text: String?
  public var tags: [String]
  public var dueFrom: String?
  public var dueTo: String?
  public var plannedFrom: String?
  public var plannedTo: String?
  public var availableFromFrom: String?
  public var availableFromTo: String?
  /// Defer-until visibility for the open lane: `visible` (hide not-yet-available
  /// tasks unless overdue), `hidden` (only not-yet-available, non-overdue tasks),
  /// or `all`/nil (no filter). Ignored for non-open status lanes.
  public var availability: String?
  public var scheduledFrom: String?
  public var scheduledTo: String?
  public var completedFrom: String?
  public var completedTo: String?
  public var createdFrom: String?
  public var createdTo: String?
  public var updatedFrom: String?
  public var updatedTo: String?
  public var duePresence: String?
  public var plannedPresence: String?
  public var blockedOnly: Bool
  public var blockingOthers: Bool
  public var sortBy: String
  public var sortDirection: String
  public var limit: Int
  public var offset: Int

  public init(
    status: String = "open",
    listID: LorvexList.ID? = nil,
    priority: Int? = nil,
    text: String? = nil,
    tags: [String] = [],
    dueFrom: String? = nil,
    dueTo: String? = nil,
    plannedFrom: String? = nil,
    plannedTo: String? = nil,
    availableFromFrom: String? = nil,
    availableFromTo: String? = nil,
    availability: String? = nil,
    scheduledFrom: String? = nil,
    scheduledTo: String? = nil,
    completedFrom: String? = nil,
    completedTo: String? = nil,
    createdFrom: String? = nil,
    createdTo: String? = nil,
    updatedFrom: String? = nil,
    updatedTo: String? = nil,
    duePresence: String? = nil,
    plannedPresence: String? = nil,
    blockedOnly: Bool = false,
    blockingOthers: Bool = false,
    sortBy: String = "priority_due",
    sortDirection: String = "asc",
    limit: Int = 100,
    offset: Int = 0
  ) {
    self.status = status
    self.listID = listID
    self.priority = priority
    self.text = text
    self.tags = tags
    self.dueFrom = dueFrom
    self.dueTo = dueTo
    self.plannedFrom = plannedFrom
    self.plannedTo = plannedTo
    self.availableFromFrom = availableFromFrom
    self.availableFromTo = availableFromTo
    self.availability = availability
    self.scheduledFrom = scheduledFrom
    self.scheduledTo = scheduledTo
    self.completedFrom = completedFrom
    self.completedTo = completedTo
    self.createdFrom = createdFrom
    self.createdTo = createdTo
    self.updatedFrom = updatedFrom
    self.updatedTo = updatedTo
    self.duePresence = duePresence
    self.plannedPresence = plannedPresence
    self.blockedOnly = blockedOnly
    self.blockingOthers = blockingOthers
    self.sortBy = sortBy
    self.sortDirection = sortDirection
    self.limit = limit
    self.offset = offset
  }
}
