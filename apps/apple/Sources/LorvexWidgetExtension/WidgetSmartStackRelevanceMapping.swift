import LorvexWidgetKitSupport
import WidgetKit

extension WidgetSmartStackRelevance {
  /// Maps the platform-neutral relevance DTO to WidgetKit's
  /// `TimelineEntryRelevance`, applying the policy's decay `duration` when present.
  /// Kept in this WidgetKit-importing module so `LorvexWidgetKitSupport` stays
  /// platform-neutral (WidgetKit-free).
  var timelineEntryRelevance: TimelineEntryRelevance {
    if let duration {
      return TimelineEntryRelevance(score: score, duration: duration)
    }
    return TimelineEntryRelevance(score: score)
  }
}
