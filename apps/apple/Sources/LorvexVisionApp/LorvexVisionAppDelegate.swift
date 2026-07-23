import LorvexCloudSync
import LorvexCore
import LorvexMobile
import LorvexSystemIntents

#if canImport(UIKit)
  import OSLog
  import UIKit
  import UserNotifications

  /// visionOS app delegate that installs the notification-center delegate so task
  /// reminders' rich actions and default taps are handled, mirroring the iOS app
  /// delegate's `UNUserNotificationCenterDelegate` half.
  ///
  /// Without this delegate the visionOS scheduler still fires reminder banners
  /// (its `init` registers the categories), but the Complete / Defer / Snooze
  /// actions route to a non-existent `didReceive` and are silently dropped, and a
  /// default tap never runs the deep-link route. visionOS registers no CloudKit
  /// push subscription, so — unlike the iOS delegate — this one does not register
  /// for remote notifications or handle Home Screen quick actions.
  final class LorvexVisionAppDelegate: NSObject, UIApplicationDelegate,
    UNUserNotificationCenterDelegate
  {
    nonisolated private static let log = Logger(
      subsystem: "com.lorvex.vision",
      category: "notifications")

    /// Posts `.lorvexNotificationActionError` so `MobileStore` surfaces a failed
    /// Complete / Defer / Snooze notification action as a user-visible alert,
    /// mirroring the iOS delegate. A `nil` message lets the store apply its own
    /// localized fallback.
    nonisolated private static func postNotificationActionError(_ message: String?) {
      var userInfo: [AnyHashable: Any] = [:]
      if let message { userInfo["errorMessage"] = message }
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
        // ring so the Settings diagnostics feed can surface them read-only,
        // mirroring the iOS delegate. Without this the visionOS "Recent
        // Diagnostics" UI renders over a permanently-empty feed.
        MetricKitDiagnosticsSubscriber.register()
      #endif

      return true
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
          } catch {
            Self.log.error(
              "Complete notification action failed for task \(taskID, privacy: .public): \(error.localizedDescription, privacy: .private)"
            )
            Self.postNotificationActionError(error.localizedDescription)
          }
        },
        deferTask: { taskID in
          do {
            _ = try await LorvexTaskIntentRunner.deferTaskUntilTomorrow(id: taskID)
          } catch {
            Self.log.error(
              "Defer notification action failed for task \(taskID, privacy: .public): \(error.localizedDescription, privacy: .private)"
            )
            Self.postNotificationActionError(error.localizedDescription)
          }
        },
        snoozeTask: { taskID in
          let title = response.notification.request.content.title
          let report = await SnoozeNotificationScheduler.schedule(
            taskID: taskID,
            title: title.isEmpty ? nil : title,
            strings: .mobileLocalized
          )
          if report.status == .failed {
            Self.postNotificationActionError(report.errorMessage)
          }
        }
      )

      // Route default taps via deep-link; the visionOS scene's
      // `lorvexMobileSystemEntrypoints` modifier handles the URL via `onOpenURL`.
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
