#if os(iOS)
  import BackgroundTasks
  import Foundation
  import OSLog

  /// Periodic background wake that re-arms the rolling reminder window while the
  /// app is suspended.
  ///
  /// Only the earliest `ReminderBudget.pendingNotificationLimit` task reminders
  /// and a bounded habit horizon are handed to the system at once; the OS frees a
  /// slot as each one-shot fires, but nothing re-arms the next batch (or reaps a
  /// consumed habit cadence's remaining same-cycle requests) until the app runs
  /// again. Foreground activation and CloudKit silent pushes already replenish the
  /// window; this closes the gap for a device left closed for days with no push,
  /// by asking iOS for a background-refresh wake that runs the same replenishment.
  ///
  /// Best-effort by design: iOS decides when — and whether — to run app-refresh
  /// tasks from usage and power heuristics, so this is an extra opportunity, not a
  /// guarantee, and never the sole delivery path. The wiring is three parts: the
  /// `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes: fetch` keys in
  /// `LorvexMobileApp-Info.plist`, the `.backgroundTask(.appRefresh:)` handler on
  /// the scene, and this request scheduler.
  enum ReminderBackgroundRefresh {
    /// Must match the `BGTaskSchedulerPermittedIdentifiers` entry in
    /// `LorvexMobileApp-Info.plist`; registering a handler for an identifier the
    /// plist does not permit traps at launch.
    static let taskIdentifier = "com.lorvex.apple.reminder-refresh"

    /// Earliest spacing before the system may run the next refresh. iOS treats it
    /// as a floor, not a schedule, and usually runs less often.
    static let earliestInterval: TimeInterval = 4 * 60 * 60  // 4 hours

    /// Submit a refresh request. Safe to call repeatedly — a resubmit replaces the
    /// pending request. A submission failure (Background App Refresh disabled by
    /// the user, simulator without support, over the pending-request cap) is
    /// logged and swallowed: foreground and push replenishment still run.
    static func schedule(now: Date = Date()) {
      let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
      request.earliestBeginDate = now.addingTimeInterval(earliestInterval)
      do {
        try BGTaskScheduler.shared.submit(request)
      } catch {
        Logger(subsystem: "com.lorvex.mobile", category: "reminders")
          .debug(
            "BGAppRefresh submit failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
#endif
