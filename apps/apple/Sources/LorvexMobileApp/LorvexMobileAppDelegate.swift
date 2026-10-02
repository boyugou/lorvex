import LorvexCloudSync
import LorvexCore
import LorvexMobile
import LorvexSystemIntents

#if canImport(UIKit)
  import OSLog
  import UIKit
  import UserNotifications

  /// iOS app delegate responsible for Home Screen quick-action activations,
  /// notification category registration, and notification action handling.
  ///
  /// Notification categories are registered at launch so rich actions
  /// (Complete, Defer, Snooze) are available on every task reminder.
  /// Action responses are dispatched to `LorvexTaskIntentRunner` via
  /// `handleLorvexNotificationAction`.
  final class LorvexMobileAppDelegate: NSObject, UIApplicationDelegate,
    UNUserNotificationCenterDelegate
  {
    @MainActor weak var store: MobileStore?

    nonisolated private static let log = Logger(
      subsystem: "com.lorvex.mobile",
      category: "notifications")

    /// Posts `.lorvexBackgroundMutationApplied` so `MobileStore` refreshes
    /// after a successful in-process Complete/Defer notification action,
    /// without coupling the app delegate to the store directly. Mirrors
    /// macOS `AppDelegate.postBackgroundMutationApplied()`.
    nonisolated private static func postBackgroundMutationApplied() {
      NotificationCenter.default.post(name: .lorvexBackgroundMutationApplied, object: nil)
    }

    /// Posts `.lorvexNotificationActionError` with the failure's classification
    /// (``LorvexNotificationActionFailure``) so `MobileStore` surfaces a failed
    /// Complete / Defer / Snooze notification action as a user-visible alert,
    /// mirroring macOS `AppDelegate.postNotificationActionFailure(_:)`. Without
    /// this the write failed, the notification was consumed, and the task stayed
    /// open with nothing shown. A `nil` classification lets the store apply its
    /// own localized fallback.
    nonisolated private static func postNotificationActionFailure(
      _ classification: UserFacingError.Classification?
    ) {
      // Record the durable breadcrumb BEFORE the in-process post: at a cold
      // background launch no observer is live, so the post vanishes and the store
      // drains this on the next foreground. Recording first means a live observer
      // (warm case) can safely clear it after surfacing, showing it exactly once.
      MobileNotificationActionErrorHandoff().record(classification)
      var userInfo: [AnyHashable: Any] = [:]
      if let classification {
        userInfo[LorvexNotificationActionFailure.classificationKey] = classification
      }
      NotificationCenter.default.post(
        name: .lorvexNotificationActionError, object: nil, userInfo: userInfo)
    }

    func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
      let center = UNUserNotificationCenter.current()
      center.delegate = self
      registerLorvexNotificationCategories(center, titles: MobileTaskReminderStrings.actionTitles)

      #if canImport(MetricKit)
        // Persist MetricKit crash/hang/CPU/disk diagnostics to the `error_logs`
        // ring so the Settings diagnostics feed can surface them read-only.
        MetricKitDiagnosticsSubscriber.register()
      #endif

      // Register for APNs so CloudKit silent (content-available) pushes from the
      // private-database subscription are delivered. Harmless without the Push
      // Notifications capability (dev builds use the base entitlements): the
      // system calls `didFailToRegisterForRemoteNotificationsWithError` instead
      // of crashing, and sync falls back to manual/foreground refresh.
      application.registerForRemoteNotifications()

      if let item = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
        LorvexShortcutHandoff.pendingTypeIdentifier = item.type
      }
      return true
    }

    func application(
      _ application: UIApplication,
      performActionFor shortcutItem: UIApplicationShortcutItem,
      completionHandler: @escaping (Bool) -> Void
    ) {
      LorvexShortcutHandoff.pendingTypeIdentifier = shortcutItem.type
      completionHandler(true)
    }

    /// Handles Lorvex's CloudKit silent pushes. The sync engine fetches on its
    /// own when one arrives; this keeps the app awake for that work within the
    /// push budget. An active app runs the full refresh so newly applied data
    /// reaches the visible views, widgets, reminders, and badge; a background
    /// wake runs only the sync pass. Before launch attaches the store, the push
    /// is left to the engine, which starts with the store and fetches then.
    func application(
      _ application: UIApplication,
      didReceiveRemoteNotification userInfo: [AnyHashable: Any],
      fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
      let info = userInfo as? [String: Any] ?? [:]
      guard CloudKitPushParser.isLorvexCloudKitNotification(info) else {
        completionHandler(.noData)
        return
      }
      Task { @MainActor [weak self] in
        guard let store = self?.store else {
          completionHandler(.noData)
          return
        }
        // A silent push is delivered to a suspended app as readily as to an
        // active one, and the drain below writes to the App Group database.
        let result = await BackgroundDatabaseWork.run {
          await store.handleCloudKitPush(
            applicationIsActive: application.applicationState == .active)
        }
        completionHandler(Self.backgroundFetchResult(for: result))
      }
    }

    private static func backgroundFetchResult(
      for result: MobileCloudSyncLifecycleResult
    ) -> UIBackgroundFetchResult {
      switch result {
      case .newData:
        return .newData
      case .noData:
        return .noData
      case .failed:
        return .failed
      }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
      _ center: UNUserNotificationCenter,
      willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
      // Include `.list` so a reminder delivered while the app is foregrounded still
      // leaves a Notification Center entry, not just a transient banner.
      [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
      _ center: UNUserNotificationCenter,
      didReceive response: UNNotificationResponse
    ) async {
      await handleLorvexNotificationAction(
        response: response,
        completeTask: { taskID in
          do {
            _ = try await LorvexTaskIntentRunner.completeTask(id: taskID)
            Self.postBackgroundMutationApplied()
          } catch {
            Self.log.error(
              "Complete notification action failed for task \(taskID, privacy: .public): \(error.localizedDescription, privacy: .private)"
            )
            Self.postNotificationActionFailure(UserFacingError.classify(error))
          }
        },
        deferTask: { taskID in
          do {
            _ = try await LorvexTaskIntentRunner.deferTaskUntilTomorrow(id: taskID)
            Self.postBackgroundMutationApplied()
          } catch {
            Self.log.error(
              "Defer notification action failed for task \(taskID, privacy: .public): \(error.localizedDescription, privacy: .private)"
            )
            Self.postNotificationActionFailure(UserFacingError.classify(error))
          }
        },
        snoozeTask: { taskID in
          let title = response.notification.request.content.title
          let report = await SnoozeNotificationScheduler.schedule(
            taskID: taskID,
            title: title.isEmpty ? nil : title,
            strings: .mobileLocalized
          )
          // A failed snooze must not vanish silently: the user tapped "Snooze"
          // and would otherwise get no reminder in an hour and see nothing.
          if report.status == .failed {
            Self.postNotificationActionFailure(
              report.errorMessage.map { UserFacingError.classify(message: $0) })
          }
        }
      )

      // Route default taps via deep-link.
      let actionID = response.actionIdentifier
      guard actionID == UNNotificationDefaultActionIdentifier else { return }
      guard
        let route = LorvexNotificationRoute(
          userInfo: response.notification.request.content.userInfo
        )
      else { return }
      await MainActor.run {
        UIApplication.shared.open(route.url)
      }
    }
  }
#endif

/// Thread-safe store for the most recently received Home Screen shortcut type.
///
/// The pending identifier is written by `LorvexMobileAppDelegate` on receipt
/// of a `UIApplicationShortcutItem` and consumed (once) by `LorvexMobileApp`
/// on the next active scene-phase transition.
@MainActor
enum LorvexShortcutHandoff {
  static var pendingTypeIdentifier: String?

  /// Returns and clears the pending identifier, or `nil` when nothing is
  /// queued.
  static func consume() -> String? {
    defer { pendingTypeIdentifier = nil }
    return pendingTypeIdentifier
  }
}
