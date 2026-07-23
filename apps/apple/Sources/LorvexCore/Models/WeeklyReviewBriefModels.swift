import Foundation

/// Weekly activity brief as served by the MCP tool `get_weekly_brief`:
/// the full section arrays with per-section pagination meta, unlike
/// ``WeeklyReviewSnapshot`` (the compact dashboard aggregate). Section sizes
/// are caller-tunable; every section reports the limit it actually applied.
public struct WeeklyReviewBriefModel: Equatable, Sendable {
  public struct Window: Equatable, Sendable {
    public var label: String
    public var days: Int

    public init(label: String, days: Int) {
      self.label = label
      self.days = days
    }
  }

  public struct TaskItem: Equatable, Sendable {
    public var id: String
    public var title: String
    public var listID: String
    public var status: String
    public var completedAt: String?
    public var dueDate: String?
    public var deferCount: Int

    public init(
      id: String, title: String, listID: String, status: String,
      completedAt: String?, dueDate: String?, deferCount: Int
    ) {
      self.id = id
      self.title = title
      self.listID = listID
      self.status = status
      self.completedAt = completedAt
      self.dueDate = dueDate
      self.deferCount = deferCount
    }
  }

  public struct StalledList: Equatable, Sendable {
    public var id: String
    public var name: String
    public var icon: String?
    public var color: String?
    public var openTaskCount: Int
    public var lastActivity: String?

    public init(
      id: String, name: String, icon: String?, color: String?,
      openTaskCount: Int, lastActivity: String?
    ) {
      self.id = id
      self.name = name
      self.icon = icon
      self.color = color
      self.openTaskCount = openTaskCount
      self.lastActivity = lastActivity
    }
  }

  public struct EstimateSummary: Equatable, Sendable {
    public var completedTotal: Int
    public var completedWithEstimateCount: Int
    public var estimateCoverageRatio: Double?

    public init(
      completedTotal: Int, completedWithEstimateCount: Int, estimateCoverageRatio: Double?
    ) {
      self.completedTotal = completedTotal
      self.completedWithEstimateCount = completedWithEstimateCount
      self.estimateCoverageRatio = estimateCoverageRatio
    }
  }

  public struct SectionEntry: Equatable, Sendable {
    public var limit: Int
    public var totalMatching: Int
    public var returned: Int
    public var truncated: Bool

    public init(limit: Int, totalMatching: Int, returned: Int, truncated: Bool) {
      self.limit = limit
      self.totalMatching = totalMatching
      self.returned = returned
      self.truncated = truncated
    }
  }

  public struct SectionMeta: Equatable, Sendable {
    public var completedThisWeek: SectionEntry
    public var stalledLists: SectionEntry
    public var frequentlyDeferred: SectionEntry
    public var somedayItems: SectionEntry

    public init(
      completedThisWeek: SectionEntry, stalledLists: SectionEntry,
      frequentlyDeferred: SectionEntry, somedayItems: SectionEntry
    ) {
      self.completedThisWeek = completedThisWeek
      self.stalledLists = stalledLists
      self.frequentlyDeferred = frequentlyDeferred
      self.somedayItems = somedayItems
    }
  }

  public var window: Window
  public var completedThisWeek: [TaskItem]
  public var stalledLists: [StalledList]
  public var frequentlyDeferred: [TaskItem]
  public var overdueCount: Int
  public var somedayItems: [TaskItem]
  public var createdThisWeek: Int
  public var estimateSummary: EstimateSummary
  public var sectionMeta: SectionMeta

  public init(
    window: Window, completedThisWeek: [TaskItem], stalledLists: [StalledList],
    frequentlyDeferred: [TaskItem], overdueCount: Int, somedayItems: [TaskItem],
    createdThisWeek: Int, estimateSummary: EstimateSummary, sectionMeta: SectionMeta
  ) {
    self.window = window
    self.completedThisWeek = completedThisWeek
    self.stalledLists = stalledLists
    self.frequentlyDeferred = frequentlyDeferred
    self.overdueCount = overdueCount
    self.somedayItems = somedayItems
    self.createdThisWeek = createdThisWeek
    self.estimateSummary = estimateSummary
    self.sectionMeta = sectionMeta
  }
}

/// Shared limit policy for the weekly brief's tunable sections.
public enum WeeklyReviewBriefLimitPolicy {
  public static let cap = 500
  public static let completedDefault = 50
  public static let stalledDefault = 50
  public static let deferredDefault = 10
  public static let somedayDefault = 20

  /// Requested limit clamped to `1...cap`; `nil` takes the section default.
  public static func bounded(_ requested: Int?, default defaultValue: Int) -> Int {
    guard let requested else { return defaultValue }
    return min(max(1, requested), cap)
  }
}
