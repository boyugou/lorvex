import Foundation
import LorvexCore

extension CarPlayTaskListController {

  /// One task on the car screen: the title, its time on the day, and the two
  /// states a driver acts on (started, overdue).
  ///
  /// `startMinutes`/`endMinutes` are the task's time as minutes since midnight
  /// in the day's timezone, `nil` when the day's schedule does not time it.
  /// Everything else is read straight from the task.
  public struct Row: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public var startMinutes: Int?
    public var endMinutes: Int?
    public var estimatedMinutes: Int?
    public var isStarted: Bool
    public var isOverdue: Bool

    public init(
      id: String, title: String,
      startMinutes: Int? = nil, endMinutes: Int? = nil, estimatedMinutes: Int? = nil,
      isStarted: Bool = false, isOverdue: Bool = false
    ) {
      self.id = id
      self.title = title
      self.startMinutes = startMinutes
      self.endMinutes = endMinutes
      self.estimatedMinutes = estimatedMinutes
      self.isStarted = isStarted
      self.isOverdue = isOverdue
    }

    /// True while the clock sits inside the task's time.
    public func isRunning(nowMinutes: Int?) -> Bool {
      guard let now = nowMinutes, let start = startMinutes, let end = endMinutes else { return false }
      return start <= now && now < end
    }
  }
}

/// The second line under a car-screen row: the task's time, else the state that
/// explains it, else its estimate. Short and glanceable; every string comes
/// from the CarPlay catalog.
public enum CarPlayRowCopy {
  public static func detail(for row: CarPlayTaskListController.Row, nowMinutes: Int?) -> String? {
    if row.isRunning(nowMinutes: nowMinutes), let end = row.endMinutes {
      return String(
        localized: "carplay.detail.until",
        defaultValue: "Until \(lorvexClockTimeLabel(minutes: end))",
        table: "Localizable", bundle: CarPlayL10n.bundle)
    }
    if let start = row.startMinutes, let end = row.endMinutes, end > start {
      return lorvexClockRangeLabel(startMinutes: start, endMinutes: end)
    }
    if row.isOverdue {
      return String(
        localized: "carplay.detail.overdue", defaultValue: "Overdue",
        table: "Localizable", bundle: CarPlayL10n.bundle)
    }
    if row.isStarted {
      if let minutes = row.estimatedMinutes, minutes > 0 {
        return String(
          localized: "carplay.detail.started_about",
          defaultValue: "Started · about \(minutes) min",
          table: "Localizable", bundle: CarPlayL10n.bundle)
      }
      return String(
        localized: "carplay.detail.started", defaultValue: "Started",
        table: "Localizable", bundle: CarPlayL10n.bundle)
    }
    if let minutes = row.estimatedMinutes, minutes > 0 {
      return String(
        localized: "carplay.detail.about", defaultValue: "About \(minutes) min",
        table: "Localizable", bundle: CarPlayL10n.bundle)
    }
    return nil
  }
}
