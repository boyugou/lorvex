import AppKit
import CloudKit
import LorvexCloudSync
import LorvexCore
import LorvexSystemIntents
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  /// Installed by the SwiftUI App after bootstrap. Weak because SwiftUI owns
  /// the root store; the delegate only coordinates a bounded normal-Quit flush.
  private weak var terminationStore: AppStore?
  private var terminationFlushIsInFlight = false
  private var terminationRequestID: UUID?

  @MainActor
  func installTerminationStore(_ store: AppStore) {
    terminationStore = store
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    #if DEBUG
      // `UNUserNotificationCenter.current()` requires a real app bundle; skip it in
      // the bare-executable `--ui-preview` run so the windows render headlessly.
      if !LorvexUIPreview.isActive {
        UNUserNotificationCenter.current().delegate = self
        registerMetricKitDiagnostics()
        registerForRemoteNotifications()
      }
    #else
      UNUserNotificationCenter.current().delegate = self
      registerMetricKitDiagnostics()
      registerForRemoteNotifications()
    #endif
    Self.recoverWindowPlacementSoon()
    Self.presentMainWindowIfNeededSoon()
  }

  /// Register for APNs so CloudKit silent (content-available) pushes from the
  /// private-database subscription reach `application(_:didReceiveRemoteNotification:)`
  /// — without this the Mac only converges on foreground/activation refresh, so
  /// an idle Mac never sees another device's changes. Harmless without the Push
  /// Notifications capability: the system calls
  /// `didFailToRegisterForRemoteNotificationsWithError` and sync falls back to
  /// foreground refresh. Mirrors the iOS delegate's registration.
  ///
  /// `@MainActor` because it is only ever called from `applicationDidFinishLaunching`
  /// (itself main-actor-isolated as an `NSApplicationDelegate` requirement) and
  /// touches the main-actor-isolated `NSApp.registerForRemoteNotifications()`.
  @MainActor
  private func registerForRemoteNotifications() {
    NSApp.registerForRemoteNotifications()
  }

  /// Persist MetricKit crash/hang/CPU/disk diagnostics to the `error_logs` ring.
  /// Registered only for the real bundle (not the `--ui-preview` executable),
  /// which `MXMetricManager` requires. macOS delivers `MXDiagnosticPayload` on
  /// 12+, well under the app's 14 floor.
  private func registerMetricKitDiagnostics() {
    #if canImport(MetricKit)
      MetricKitDiagnosticsSubscriber.register()
    #endif
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    false
  }

  /// Delay a normal Quit only when an autosave surface is dirty. SwiftUI view
  /// teardown can cancel a debounce or an `onDisappear` task; AppKit's
  /// terminate-later handshake keeps the process alive until the canonical
  /// SQLite writes settle. Force Quit/process death remain outside this API's
  /// guarantees, so normal editing still autosaves eagerly.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminationFlushIsInFlight else { return .terminateLater }
    guard let terminationStore, terminationStore.hasPendingAutosaveDraftForTermination else {
      return .terminateNow
    }

    let requestID = UUID()
    terminationFlushIsInFlight = true
    terminationRequestID = requestID
    Task { @MainActor [weak self, weak sender, weak terminationStore] in
      let didFlush = await terminationStore?.flushPendingAutosaveDraftsForTermination() ?? false
      self?.finishTerminationRequest(requestID, sender: sender, allow: didFlush)
    }
    Task { @MainActor [weak self, weak sender] in
      try? await Task.sleep(for: .seconds(10))
      guard !Task.isCancelled else { return }
      // A wedged database or filesystem must not leave AppKit waiting forever.
      // Abort this Quit attempt; the app remains open with the dirty draft and
      // can surface/retry the underlying save instead of losing data.
      self?.finishTerminationRequest(requestID, sender: sender, allow: false)
    }
    return .terminateLater
  }

  @MainActor
  private func finishTerminationRequest(
    _ requestID: UUID,
    sender: NSApplication?,
    allow: Bool
  ) {
    guard terminationRequestID == requestID else { return }
    terminationRequestID = nil
    terminationFlushIsInFlight = false
    sender?.reply(toApplicationShouldTerminate: allow)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !flag || !LorvexWindowPlacement.bringUsableWindowForwardOrRecover() {
      Self.presentMainWindowIfNeeded()
      return false
    }
    return true
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    // Include `.list` so a reminder delivered while the app is foregrounded still
    // leaves a Notification Center entry the user can return to, not just a
    // transient banner.
    [.banner, .list, .sound]
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    await handleLorvexNotificationAction(
      response: response,
      completeTask: { taskID in
        do {
          _ = try await LorvexTaskIntentRunner.completeTask(
            id: taskID,
            core: LorvexCoreRuntimeFactory.makeForNotification())
        } catch {
          postNotificationActionError(error)
        }
      },
      deferTask: { taskID in
        do {
          _ = try await LorvexTaskIntentRunner.deferTaskUntilTomorrow(
            id: taskID,
            core: LorvexCoreRuntimeFactory.makeForNotification())
        } catch {
          postNotificationActionError(error)
        }
        await MainActor.run {
          NSApp.activate()
        }
      },
      snoozeTask: { taskID in
        let title = response.notification.request.content.title
        await scheduleSnoozeNotification(taskID: taskID, title: title)
      }
    )

    // Route default notification taps via deep-link.
    let actionID = response.actionIdentifier
    guard actionID == UNNotificationDefaultActionIdentifier else { return }
    guard
      let route = LorvexNotificationRoute(
        userInfo: response.notification.request.content.userInfo
      )
    else { return }
    await MainActor.run {
      NSApp.activate()
      NSWorkspace.shared.open(route.url)
    }
  }

  func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    LorvexDockMenuBuilder.build { action in
      NSWorkspace.shared.open(action.dockFallbackDeepLink)
    }
  }

  /// Handles silent CloudKit push notifications and posts
  /// `.lorvexCloudKitRemoteChange` so AppStore can trigger a refresh.
  func application(
    _ application: NSApplication,
    didReceiveRemoteNotification userInfo: [String: Any]
  ) {
    guard CloudKitPushParser.isLorvexCloudKitNotification(userInfo) else { return }
    NotificationCenter.default.post(name: .lorvexCloudKitRemoteChange, object: nil)
  }

  private static func presentMainWindowIfNeededSoon() {
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(450))
      Self.presentMainWindowIfNeeded()
    }
  }

  private static func recoverWindowPlacementSoon() {
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(250))
      LorvexWindowPlacement.clampVisibleWindowsToScreens()
    }
  }

  @MainActor
  private static func presentMainWindowIfNeeded() {
    if LorvexWindowPlacement.bringUsableWindowForwardOrRecover() {
      return
    }
    NSApp.activate()
    #if DEBUG
      // The bare-executable `--ui-preview` isn't a registered bundle, so opening a
      // `lorvex://` URL pops a "no application set to open" dialog. Its WindowGroup
      // already shows the window, so skip the URL fallback.
      if LorvexUIPreview.isActive { return }
    #endif
    NSWorkspace.shared.open(LorvexDeepLinkRoute.destination(.today).url)
  }
}

/// Schedules a one-shot snooze notification 1 hour from now for the given task ID.
/// `title` is the original notification title so the snooze carries the task name.
private func scheduleSnoozeNotification(taskID: String, title: String? = nil) async {
  let report = await SnoozeNotificationScheduler.schedule(
    taskID: taskID, title: title, strings: .lorvexLocalized)
  // Surface a failed snooze the same way Complete/Defer surface theirs — without
  // this the user taps "Snooze", gets no reminder in an hour, and sees nothing.
  if report.status == .failed {
    postNotificationActionError(
      NotificationActionError(
        message: report.errorMessage
          ?? String(
            localized: "notification.snooze.failed", defaultValue: "Couldn't snooze the reminder.",
            table: "Localizable", bundle: LorvexL10n.bundle)))
  }
}

/// Minimal `Error` wrapper so a `TaskReminderScheduleReport` failure message can
/// flow through `postNotificationActionError`.
private struct NotificationActionError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

/// Posts `.lorvexNotificationActionError` so AppStore can surface the failure
/// as a toast without creating a direct dependency between AppDelegate and AppStore.
private func postNotificationActionError(_ error: Error) {
  NotificationCenter.default.post(
    name: .lorvexNotificationActionError,
    object: nil,
    userInfo: ["errorMessage": error.localizedDescription]
  )
}
