import Foundation
import LorvexCloudSync
import LorvexCore
import LorvexDomain
import LorvexSystemIntents
import TipKit
import UserNotifications

enum LorvexAppleBootstrap {
  static func configure() {
    AppLayoutStateReset.removeStaleMainWindowAutosaveState()
    // In-process App Intents, Spotlight queries, and notification actions resolve
    // their core through LorvexCoreRuntimeFactory. No database-location provider is
    // installed: every surface opens the single Lorvex-managed App Group store the
    // factory resolves by default (honoring a launch-time `LORVEX_APPLE_DB_PATH`
    // override on unsandboxed dev builds).
    // Every ordinary core mutation made inside this process invalidates all
    // independent window stores (main + detached); successful inbound-sync
    // reports post the same signal explicitly. The Darwin observer relays MCP
    // host and interactive-widget writes. All paths converge on one throttled /
    // single-flight AppStore refresh route.
    DatabaseChangeSignal.configureApplicationProcess()
    configureTips()
  }

  @MainActor
  static func makeSettings() -> AppSettingsStore {
    AppSettingsStore()
  }

  @MainActor
  static func makeStore(settings: AppSettingsStore) -> AppStore {
    let core = AppCoreFactory.make()
    let cloudSyncMode = AppCoreFactory.resolveCloudSyncMode(
      persistedMode: settings.cloudSyncMode,
      environment: settings.environment
    )
    // Construct exactly one coordinator actor graph for this CloudSyncState
    // directory. Live sync and off-mode maintenance share the value (including
    // its operation gate); creating separate values here would let delete,
    // re-enable, reset, and ordinary cycles race the same durable safety files.
    let cloudDataMaintenanceCoordinator = AppCoreFactory.makeCloudDataMaintenanceCoordinator()
    return AppStore(
      core: core,
      feedbackProvider: AppKitFeedbackProvider(),
      taskSearchIndexer: SpotlightTaskSearchIndexer(),
      contentSearchIndexer: SpotlightContentSearchIndexer(),
      taskReminderScheduler: UserNotificationTaskReminderScheduler(
        fallbackBody: String(
          localized: "task.reminder.notification.fallback_body",
          defaultValue: "Lorvex task reminder",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        actionTitles: LorvexNotificationActionTitles(
          complete: String(
            localized: "notification.action.complete", defaultValue: "Complete",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          deferToTomorrow: String(
            localized: "notification.action.defer_tomorrow", defaultValue: "Defer to Tomorrow",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          snooze: String(
            localized: "notification.action.snooze_hour", defaultValue: "Snooze 1 Hour",
            table: "Localizable",
            bundle: LorvexL10n.bundle))),
      habitReminderScheduler: UserNotificationHabitReminderScheduler(
        body: String(
          localized: "habit.reminder.notification.body",
          defaultValue: "Time for your habit",
          table: "Localizable",
          bundle: LorvexL10n.bundle)),
      widgetSnapshotPublisher: FileWidgetSnapshotPublisher.configuredFromEnvironment()
        ?? NoopWidgetSnapshotPublisher(),
      cloudSyncMode: cloudSyncMode,
      cloudSyncSubscriber: AppCoreFactory.makeCloudSyncSubscriber(settings: settings),
      cloudSyncCoordinator: cloudSyncMode == .live ? cloudDataMaintenanceCoordinator : nil,
      cloudDataMaintenanceCoordinator: cloudDataMaintenanceCoordinator,
      eventKitCoordinator: makeEventKitCoordinator(core: core, settings: settings),
      eventKitIntegrationEnabled: settings.eventKitEnabled,
      badgeEnabled: settings.badgeEnabled,
      isSetupCompleted: settings.setupCompleted,
      notificationAuthorizationStatusProvider: {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
      },
      clearDeliveredNotificationsForFactoryReset: {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
      },
      setBadge: BadgeCoordinator.liveBadgeSetter
    )
  }

  /// Builds the EventKit two-way coordinator over a `LiveEventKitAccess`. The
  /// access tier + enable toggle are read live from `settings` (main actor);
  /// the dedicated Lorvex calendar identifier is cached in `UserDefaults`. Nil
  /// when the backend does not expose the provider mirror (preview core).
  @MainActor
  private static func makeEventKitCoordinator(
    core: any LorvexCoreServicing, settings: AppSettingsStore
  ) -> EventKitCoordinator? {
    let suiteName =
      settings.defaults == .standard
      ? nil : LorvexProductMetadata.appGroupIdentifier
    let calendarIDKey = "eventKit.lorvexCalendarID"
    let latchKey = EventKitAccessLatch.calendarKey
    let access = LiveEventKitAccess(
      loadCalendarID: {
        let d = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        return d.string(forKey: calendarIDKey)
      },
      saveCalendarID: { id in
        let d = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        d.set(id, forKey: calendarIDKey)
      },
      loadConfirmedReadAccess: {
        let d = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        return d.bool(forKey: latchKey)
      },
      saveConfirmedReadAccess: { granted in
        let d = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        d.set(granted, forKey: latchKey)
      }
    )
    return EventKitCoordinator.make(
      core: core,
      access: access,
      loadAccessMode: { [core] in
        await effectiveCalendarAiAccessMode(core: core)
      },
      loadCalendarFilter: { [weak settings] in
        await MainActor.run { settings?.eventKitCalendarFilter ?? .all }
      },
      isEnabled: { [weak settings] in
        await MainActor.run { settings?.eventKitEnabled ?? false }
      }
    )
  }

  /// The calendar AI-access tier the EventKit ingest should mirror at, read from
  /// the core's persisted `calendar_ai_access_mode` device-state.
  ///
  /// Reading the persisted tier — rather than a pinned UI value — is what lets a
  /// core-side downgrade hold: a calendar-settings or App-Intents `set_preference`
  /// (or `delete_preference`) that reduces detail purges the mirror, and the next
  /// calendar refresh re-ingests at the now-stricter tier instead of silently
  /// re-mirroring verbatim full detail.
  ///
  /// Fail-safe direction matters for a privacy control: missing, unreadable, or
  /// corrupt state falls back to the domain default (`busy_only`), never to
  /// maximum exposure. Full detail requires an explicit device-local choice.
  static func effectiveCalendarAiAccessMode(
    core: any LorvexCoreServicing
  ) async -> CalendarAiAccessMode {
    let raw: String?
    do {
      raw = try await core.getPreference(key: PreferenceKeys.devCalendarAiAccessMode)
    } catch {
      return CalendarAiAccessMode.defaultMode
    }
    guard let raw else { return CalendarAiAccessMode.defaultMode }
    guard let mode = CalendarAiAccessMode.parseStrict(raw) else {
      return CalendarAiAccessMode.defaultMode
    }
    return mode
  }

  private static func configureTips() {
    try? Tips.configure([
      .displayFrequency(.immediate),
      .datastoreLocation(.applicationDefault),
    ])
  }

}
