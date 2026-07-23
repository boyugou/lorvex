import Foundation

public struct ListCatalogSnapshot: Equatable, Sendable {
  public var lists: [LorvexList]

  public init(lists: [LorvexList]) {
    self.lists = lists
  }
}

public struct ListDetailSnapshot: Equatable, Sendable {
  public var list: LorvexList
  public var tasks: [LorvexTask]
  public var totalMatching: Int
  public var returned: Int
  public var limit: Int
  public var offset: Int
  public var nextOffset: Int?
  public var truncated: Bool

  public init(
    list: LorvexList,
    tasks: [LorvexTask],
    totalMatching: Int,
    returned: Int,
    limit: Int,
    offset: Int,
    nextOffset: Int?,
    truncated: Bool
  ) {
    self.list = list
    self.tasks = tasks
    self.totalMatching = totalMatching
    self.returned = returned
    self.limit = limit
    self.offset = offset
    self.nextOffset = nextOffset
    self.truncated = truncated
  }
}

public struct ListHealthEntry: Identifiable, Equatable, Sendable {
  public var id: String
  public var name: String
  public var color: String?
  public var icon: String?
  public var openCount: Int
  public var overdueOpenCount: Int
  public var dueTodayOpenCount: Int

  public init(
    id: String,
    name: String,
    color: String?,
    icon: String?,
    openCount: Int,
    overdueOpenCount: Int,
    dueTodayOpenCount: Int
  ) {
    self.id = id
    self.name = name
    self.color = color
    self.icon = icon
    self.openCount = openCount
    self.overdueOpenCount = overdueOpenCount
    self.dueTodayOpenCount = dueTodayOpenCount
  }
}

public struct ListHealthSnapshot: Equatable, Sendable {
  public var date: String
  public var totalLists: Int
  public var lists: [ListHealthEntry]

  public init(date: String, totalLists: Int, lists: [ListHealthEntry]) {
    self.date = date
    self.totalLists = totalLists
    self.lists = lists
  }
}

public struct LorvexList: Identifiable, Equatable, Sendable {
  public var id: String
  public var name: String
  public var color: String?
  public var icon: String?
  public var description: String?
  /// AI-authored scope/profile notes for the whole list (AI-only, mirroring
  /// task ai_notes). Written via MCP create_list/update_list; never human-edited.
  public var aiNotes: String?
  public var openCount: Int
  public var completedCount: Int
  public var cancelledCount: Int
  public var totalCount: Int
  public var updatedAt: String
  /// Soft-archive timestamp (ISO-8601). Non-nil = the whole list is archived:
  /// kept with all its tasks (completed history intact) but hidden from the
  /// active sidebar, restorable from the archived view. Orthogonal to deletion.
  public var archivedAt: String?
  /// Synced manual display order in the list catalog.
  public var position: Int64

  public init(
    id: String,
    name: String,
    color: String?,
    icon: String?,
    description: String?,
    aiNotes: String? = nil,
    openCount: Int,
    completedCount: Int = 0,
    cancelledCount: Int = 0,
    totalCount: Int,
    updatedAt: String,
    archivedAt: String? = nil,
    position: Int64 = 0
  ) {
    self.id = id
    self.name = name
    self.color = color
    self.icon = icon
    self.description = description
    self.aiNotes = aiNotes
    self.openCount = openCount
    self.completedCount = completedCount
    self.cancelledCount = cancelledCount
    self.totalCount = totalCount
    self.updatedAt = updatedAt
    self.archivedAt = archivedAt
    self.position = position
  }

  /// Whether this list is archived (set aside), `archivedAt != nil`.
  public var isArchived: Bool { archivedAt != nil }

  /// Tasks counted in the list-as-project progress denominator
  /// (`totalCount - cancelledCount`). A cancelled task isn't "remaining work",
  /// so it doesn't drag the bar — only open + completed tasks count.
  public var progressDenominator: Int { max(0, totalCount - cancelledCount) }

  /// Fractional completion in `0...1`. `nil` when the denominator is zero
  /// (so the UI can hide the progress affordance on empty lists).
  public var progressFraction: Double? {
    let denom = progressDenominator
    guard denom > 0 else { return nil }
    return Double(completedCount) / Double(denom)
  }
}
