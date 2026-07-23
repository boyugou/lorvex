import Foundation
import LorvexWidgetKitSupport
import WidgetKit

/// A timeline entry for the Lorvex watch face complication.
///
/// Carries enough state for every family (circular / rectangular / inline /
/// corner) to render correctly without any per-family fork in the producer:
/// `taskTitle` / `statusText` / `openFocusCount` drive the next-task layout.
public struct LorvexWatchComplicationEntry: TimelineEntry, Equatable, Sendable {
  /// The date at which this entry becomes active.
  public let date: Date

  /// The title of the current primary focus task, or `nil` when no task exists.
  public let taskTitle: String?

  /// A one-line status suitable for an accessoryInline face or subtitle.
  ///
  /// Examples: "1 focus task", "No focus", "2 tasks".
  public let statusText: String

  /// Count of actionable focus tasks (`open` or `in_progress`). The historical
  /// property name is retained because the value is shared across widget views.
  public let openFocusCount: Int

  /// Distinguishes a real empty focus plan from a snapshot that could not be
  /// loaded. Compact views must never present the latter as reassuringly empty.
  public let availability: FocusGlancePresentation.Availability

  /// Priority tier (1–3, P1 highest) of the primary focus task, or `nil` when
  /// there is no focus task or its priority is unset. Drives the rectangular
  /// layout's priority dot.
  public let primaryPriorityTier: Int?

  /// Product timezone captured with the snapshot that produced this entry.
  public let timezoneName: String?

  /// `true` for the system-requested placeholder entry (before real data has
  /// loaded), so the view can apply `.redacted(reason: .placeholder)` and read
  /// as loading rather than as a real "1 focus task" state.
  public let isPlaceholder: Bool

  /// Smart Stack relevance scaled by the actionable focus task count, or `nil` (the
  /// `TimelineEntry` default — "not specially relevant") when there are none.
  public var relevance: TimelineEntryRelevance? {
    WidgetSmartStackRelevancePolicy.relevance(
      taskCount: openFocusCount,
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
    taskTitle: String?,
    statusText: String,
    openFocusCount: Int = 0,
    availability: FocusGlancePresentation.Availability = .content,
    primaryPriorityTier: Int? = nil,
    timezoneName: String? = nil,
    isPlaceholder: Bool = false
  ) {
    self.date = date
    self.taskTitle = taskTitle
    self.statusText = statusText
    self.openFocusCount = openFocusCount
    self.availability = availability
    self.primaryPriorityTier = primaryPriorityTier
    self.timezoneName = timezoneName
    self.isPlaceholder = isPlaceholder
  }
}
