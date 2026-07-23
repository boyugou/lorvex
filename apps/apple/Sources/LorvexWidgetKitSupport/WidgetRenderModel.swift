import Foundation
import LorvexCore

public enum WidgetFamilyKind: Equatable, Sendable {
  case systemSmall
  case systemMedium
  case systemLarge
  case accessoryInline
  case accessoryRectangular
  case accessoryCircular

  public var maxTaskRows: Int {
    switch self {
    case .accessoryInline, .accessoryCircular:
      0
    case .systemSmall, .accessoryRectangular:
      2
    case .systemMedium:
      3
    case .systemLarge:
      6
    }
  }
}

public enum WidgetRenderState: Equatable, Sendable {
  case content
  case empty
  case stale
  case fallback
}

public struct WidgetTaskRenderRow: Equatable, Sendable, Identifiable {
  public let id: String
  public let title: String
  public let metadata: String?
  public let priorityLabel: String?
  /// Priority tier 1–3 (P1 highest). Drives the row's colored priority dot in the
  /// system widgets; `nil` renders no dot. Kept alongside `priorityLabel` so the
  /// accessory/inline families can still spell the priority out as text.
  public let priorityTier: Int?
  public let urlString: String?

  public init(
    id: String,
    title: String,
    metadata: String?,
    priorityLabel: String?,
    priorityTier: Int? = nil,
    urlString: String? = nil
  ) {
    self.id = id
    self.title = title
    self.metadata = metadata
    self.priorityLabel = priorityLabel
    self.priorityTier = priorityTier
    self.urlString = urlString
  }
}

public struct WidgetRenderModel: Equatable, Sendable {
  public let family: WidgetFamilyKind
  public let state: WidgetRenderState
  public let headline: String
  public let subheadline: String
  public let statusText: String
  public let staleAgeLabel: String?
  public let focusCountText: String
  /// Raw focus task count, available as an integer without string parsing.
  public let focusCount: Int
  /// Tasks completed today across the workspace. This is not a focus-progress
  /// numerator and must not be combined with `focusCount` as though both values
  /// described the same task cohort.
  public let completedCount: Int
  public let attentionCountText: String?
  public let taskRows: [WidgetTaskRenderRow]
  public let urlString: String?

  public init(
    family: WidgetFamilyKind,
    state: WidgetRenderState,
    headline: String,
    subheadline: String,
    statusText: String,
    staleAgeLabel: String? = nil,
    focusCountText: String,
    focusCount: Int = 0,
    completedCount: Int = 0,
    attentionCountText: String?,
    taskRows: [WidgetTaskRenderRow],
    urlString: String? = nil
  ) {
    self.family = family
    self.state = state
    self.headline = headline
    self.subheadline = subheadline
    self.statusText = statusText
    self.staleAgeLabel = staleAgeLabel
    self.focusCountText = focusCountText
    self.focusCount = max(0, focusCount)
    self.completedCount = max(0, completedCount)
    self.attentionCountText = attentionCountText
    self.taskRows = taskRows
    self.urlString = urlString
  }
}
