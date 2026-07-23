import Foundation

/// A truthful, surface-independent interpretation of the focus snapshot.
///
/// A failed or expired snapshot is not an empty focus plan. Control Center and
/// watch complications use this projection so every compact surface preserves
/// that distinction.
public struct FocusGlancePresentation: Equatable, Sendable {
  public enum Availability: Equatable, Sendable {
    case unavailable
    case empty
    case content
  }

  public let availability: Availability
  public let primaryTask: WidgetSnapshot.FocusTask?
  public let actionableCount: Int
  public let timezoneName: String?

  public static func resolve(
    from result: WidgetSnapshotLoadResult,
    now: Date,
    calendar: Calendar = .autoupdatingCurrent
  ) -> FocusGlancePresentation {
    let validated = WidgetSnapshotFreshnessPolicy().validatingCurrentDay(
      result, now: now, calendar: calendar)
    guard case .snapshot(let snapshot) = validated else {
      return FocusGlancePresentation(
        availability: .unavailable,
        primaryTask: nil,
        actionableCount: 0,
        timezoneName: nil)
    }

    let actionable = snapshot.actionableFocusTasks
    guard let primaryTask = actionable.first else {
      return FocusGlancePresentation(
        availability: .empty,
        primaryTask: nil,
        actionableCount: 0,
        timezoneName: snapshot.timezone)
    }
    return FocusGlancePresentation(
      availability: .content,
      primaryTask: primaryTask,
      actionableCount: actionable.count,
      timezoneName: snapshot.timezone)
  }
}
