import Foundation
import UserNotifications

/// Computes and applies the app-icon badge count from a task list.
///
/// The badge count is the number of actionable (open or started) tasks that are
/// overdue or due today.
/// Gated behind `badgeEnabled`; passing `false` clears the badge to zero.
public struct BadgeCoordinator: Sendable {
  public let badgeEnabled: Bool
  public let today: String
  public let setBadge: @Sendable (Int) async -> Void

  public init(
    badgeEnabled: Bool,
    today: String,
    setBadge: @escaping @Sendable (Int) async -> Void = BadgeCoordinator.noOpBadgeSetter
  ) {
    self.badgeEnabled = badgeEnabled
    self.today = today
    self.setBadge = setBadge
  }

  /// Sets the badge count derived from `tasks`, or clears it when disabled.
  public func update(tasks: [LorvexTask]) async {
    let count = badgeEnabled ? Self.badgeCount(tasks: tasks, today: today) : 0
    await setBadge(count)
  }

  /// Returns the number of actionable tasks due today or overdue.
  ///
  /// A task is counted when its status is actionable (`open` or `in_progress`,
  /// so a started task keeps its badge) and its action date — planned-first with
  /// a deadline fallback (`planned_date ?? due_date`) — is on or before `today`
  /// (ISO-8601 `yyyy-MM-dd`).
  public static func badgeCount(tasks: [LorvexTask], today: String) -> Int {
    tasks.filter { task in
      guard task.status.isActionable else { return false }
      guard let actionDate = task.plannedDate ?? task.dueDate else { return false }
      return Self.ymdString(from: actionDate) <= today
    }.count
  }

  /// Live badge setter using UNUserNotificationCenter (iOS 16+ / macOS 13+).
  ///
  /// Inject this from the real app entry point. The unit-test process has no
  /// notification capability and `setBadgeCount` raises an NSException there;
  /// the default in `init(...)` is `noOpBadgeSetter` for that reason.
  public static let liveBadgeSetter: @Sendable (Int) async -> Void = { count in
    #if os(watchOS)
      // watchOS has no app icon badge surface; `setBadgeCount` is unavailable.
      _ = count
    #else
      do {
        try await UNUserNotificationCenter.current().setBadgeCount(count)
      } catch {
        // Badge update failures are non-fatal; silently ignore.
      }
    #endif
  }

  /// Safe default that performs no system mutation; used by tests and any
  /// non-app caller that constructs a `BadgeCoordinator` without injection.
  public static let noOpBadgeSetter: @Sendable (Int) async -> Void = { _ in }

  // Stored due dates are UTC-midnight day anchors (PlannedDayBridge's storage
  // frame), so the day they NAME is their UTC ymd. Rendering them in the local
  // frame shifted the day west of UTC — tomorrow's tasks inflated the badge
  // all evening.
  private static var ymdFormatter: DateFormatter { LorvexDateFormatters.ymdUTC }

  private static func ymdString(from date: Date) -> String {
    ymdFormatter.string(from: date)
  }
}
