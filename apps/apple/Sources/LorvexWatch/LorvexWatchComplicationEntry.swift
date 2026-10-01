import Foundation
import LorvexWidgetKitSupport
import WidgetKit

/// A timeline entry for the Lorvex watch face complication.
///
/// Carries the shared widget render model resolved at the entry's date, so the
/// complication names the same lead task, with the same line ("Until 3:00 PM",
/// "Overdue", "Started", its estimate), as the widgets and the watch app. Every
/// family reads what it has room for from the one model.
public struct LorvexWatchComplicationEntry: TimelineEntry, Equatable, Sendable {
  /// The date at which this entry becomes active.
  public let date: Date

  /// Today at `date`: the lead task, the task after it, how many are left, or
  /// that the snapshot could not be read.
  public let model: WidgetRenderModel

  /// Product timezone captured with the snapshot that produced this entry.
  public let timezoneName: String?

  /// `true` for the system-requested placeholder entry (before real data has
  /// loaded), so the view can apply `.redacted(reason: .placeholder)` and read
  /// as loading rather than as a real day.
  public let isPlaceholder: Bool

  /// Smart Stack relevance scaled by how many tasks are left, or `nil` (the
  /// `TimelineEntry` default — "not specially relevant") when none are.
  public var relevance: TimelineEntryRelevance? {
    WidgetSmartStackRelevancePolicy.relevance(
      taskCount: model.remainingCount,
      date: date,
      timezoneName: timezoneName
    )
    .map {
      if let duration = $0.duration {
        return TimelineEntryRelevance(score: $0.score, duration: duration)
      }
      return TimelineEntryRelevance(score: $0.score)
    }
  }

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
}
