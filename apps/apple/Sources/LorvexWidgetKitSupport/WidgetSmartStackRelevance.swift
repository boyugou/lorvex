import Foundation

public struct WidgetSmartStackRelevance: Equatable, Sendable {
  public let score: Float
  public let duration: TimeInterval?

  public init(score: Float, duration: TimeInterval? = nil) {
    self.score = score
    self.duration = duration
  }
}

public enum WidgetSmartStackRelevancePolicy {
  public static func relevance(
    taskCount: Int,
    date: Date,
    timezoneName: String? = nil
  ) -> WidgetSmartStackRelevance? {
    guard taskCount > 0 else { return nil }
    let score = Float(min(80, 30 + taskCount * 5))
    // "You have tasks today" stays relevant until the end of the snapshot's
    // product day. A device-local boundary can expire the same snapshot early or
    // late when the configured Lorvex timezone differs from the device timezone.
    var calendar = Calendar.autoupdatingCurrent
    if let timezoneName, let timezone = TimeZone(identifier: timezoneName) {
      calendar.timeZone = timezone
    }
    let startOfDay = calendar.startOfDay(for: date)
    let duration = calendar.date(byAdding: .day, value: 1, to: startOfDay)
      .map { $0.timeIntervalSince(date) }
      .flatMap { $0 > 0 ? $0 : nil }
    return WidgetSmartStackRelevance(score: score, duration: duration)
  }
}
