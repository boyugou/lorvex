import Foundation
import LorvexWidgetKitSupport
import WidgetKit

public struct LorvexWidgetEntry: TimelineEntry, Equatable {
  public let date: Date
  public let model: WidgetRenderModel
  /// Product timezone captured with the snapshot that produced `model`.
  public let timezoneName: String?

  /// `true` for the system-requested placeholder entry (before real data has
  /// loaded), so the entry view can apply `.redacted(reason: .placeholder)`
  /// and read as loading rather than as real (if coincidentally empty) content.
  public let isPlaceholder: Bool

  public init(
    date: Date,
    model: WidgetRenderModel,
    timezoneName: String? = nil,
    isPlaceholder: Bool = false
  ) {
    self.date = date
    self.model = model
    self.timezoneName = timezoneName
    self.isPlaceholder = isPlaceholder
  }

  public var relevance: TimelineEntryRelevance? {
    WidgetSmartStackRelevancePolicy.relevance(
      taskCount: max(model.focusCount, model.taskRows.count),
      date: date,
      timezoneName: timezoneName
    ).map(\.timelineEntryRelevance)
  }
}
