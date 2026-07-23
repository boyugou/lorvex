import Foundation
import LorvexCloudSync
import LorvexCore
import LorvexWidgetKitSupport
import UserNotifications

public struct MobileStoreFactory {
  /// Application Support subdirectory for CloudSync's account/consent safety
  /// state and reconstructible CKRecord system-fields cache. Change tokens live
  /// transactionally in the managed SQLite database. iOS and visionOS each run
  /// in their own sandbox, so the shared name does not collide across apps.
  static let cloudSyncStateAppName = "LorvexMobile"

  public typealias CoreFactory = ([String: String]) -> any LorvexCoreServicing
  public typealias FeedbackProviderFactory = () -> any LorvexFeedbackProviding
  public typealias TaskReminderSchedulerFactory = () -> any TaskReminderScheduling
  public typealias HabitReminderSchedulerFactory = () -> any HabitReminderScheduling
  public typealias WidgetSnapshotPublisherFactory =
    (any LorvexCoreServicing) -> any MobileWidgetSnapshotPublishing
  public typealias BadgeSetter = @Sendable (Int) async -> Void
  public typealias SetupPreferencesFactory = () -> MobileSetupPreferences
  public typealias NotificationAuthorizationStatusProvider = @Sendable () async -> UNAuthorizationStatus

  private let environment: [String: String]
  private let coreFactory: CoreFactory
  private let feedbackProviderFactory: FeedbackProviderFactory
  private let taskReminderSchedulerFactory: TaskReminderSchedulerFactory
  private let habitReminderSchedulerFactory: HabitReminderSchedulerFactory
  private let widgetSnapshotPublisherFactory: WidgetSnapshotPublisherFactory
  private let setBadge: BadgeSetter
  private let setupPreferencesFactory: SetupPreferencesFactory
  private let notificationAuthorizationStatusProvider: NotificationAuthorizationStatusProvider
  private let todayString: @Sendable () -> String
  private let now: @Sendable () -> Date

  public init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    coreFactory: @escaping CoreFactory = LorvexCoreRuntimeFactory.makeForMobile(environment:),
    feedbackProviderFactory: @escaping FeedbackProviderFactory = { NoOpFeedbackProvider() },
    taskReminderSchedulerFactory: @escaping TaskReminderSchedulerFactory = {
      NoopTaskReminderScheduler()
    },
    habitReminderSchedulerFactory: @escaping HabitReminderSchedulerFactory = {
      NoopHabitReminderScheduler()
    },
    widgetSnapshotPublisherFactory: @escaping WidgetSnapshotPublisherFactory = { core in
      #if os(iOS)
        // Bind every mirrored snapshot to the exact database instance that
        // produced it. The watch must observe this baseline before it can mint a
        // command, and a later database replacement invalidates queued commands
        // from the earlier workspace.
        let mirror: @Sendable (WidgetSnapshot) async -> Void
        if let commandService = core as? any LorvexWatchCommandServicing {
          let watchMirror = WatchSnapshotReplicaMirror(
            commandService: commandService,
            publisher: WCSessionWatchSnapshotPublisher())
          mirror = { snapshot in
            await watchMirror.publish(snapshot: snapshot)
          }
        } else {
          assertionFailure("Mobile core does not provide the Watch command contract")
          mirror = { _ in }
        }
        return MobileFileWidgetSnapshotPublisher.configuredFromEnvironment(mirror: mirror)
          ?? NoopMobileWidgetSnapshotPublisher()
      #else
        return MobileFileWidgetSnapshotPublisher.configuredFromEnvironment()
          ?? NoopMobileWidgetSnapshotPublisher()
      #endif
    },
    setBadge: @escaping BadgeSetter = BadgeCoordinator.noOpBadgeSetter,
    setupPreferencesFactory: @escaping SetupPreferencesFactory = { MobileSetupPreferences() },
    // Safe, inert default: "already resolved" so a factory-level test that
    // never overrides this never touches the real `UNUserNotificationCenter`
    // (unavailable in the SwiftPM test-runner process). `LorvexMobileApp` /
    // `LorvexVisionApp` override with the live system read.
    notificationAuthorizationStatusProvider: @escaping NotificationAuthorizationStatusProvider = {
      .authorized
    },
    todayString: @escaping @Sendable () -> String = MobileStore.defaultTodayString,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.environment = environment
    self.coreFactory = coreFactory
    self.feedbackProviderFactory = feedbackProviderFactory
    self.taskReminderSchedulerFactory = taskReminderSchedulerFactory
    self.habitReminderSchedulerFactory = habitReminderSchedulerFactory
    self.widgetSnapshotPublisherFactory = widgetSnapshotPublisherFactory
    self.setBadge = setBadge
    self.setupPreferencesFactory = setupPreferencesFactory
    self.notificationAuthorizationStatusProvider = notificationAuthorizationStatusProvider
    self.todayString = todayString
    self.now = now
  }

  @MainActor
  public func makeStore(selectedTab: MobileTab = .today) -> MobileStore {
    let prefs = setupPreferencesFactory()
    let containerID = LorvexProductMetadata.cloudKitContainerIdentifier
    let cloudSyncMode = CloudSyncFactory.resolveMode(
      persistedMode: prefs.cloudSyncMode,
      environment: environment
    )
    let stateDirectory = CloudSyncFactory.stateDirectory(
      appName: Self.cloudSyncStateAppName,
      containerIdentifier: containerID
    )
    // One coordinator value owns the sync-state directory for the store's
    // entire lifetime. Off-mode maintenance and later live-mode transitions
    // reuse it instead of constructing independently gated file-store actors.
    let cloudDataMaintenanceCoordinator = CloudSyncFactory.makeCoordinator(
      mode: .live,
      containerIdentifier: containerID,
      stateDirectory: stateDirectory
    )
    let core = coreFactory(environment)
    return MobileStore(
      core: core,
      feedbackProvider: feedbackProviderFactory(),
      taskReminderScheduler: taskReminderSchedulerFactory(),
      habitReminderScheduler: habitReminderSchedulerFactory(),
      widgetSnapshotPublisher: widgetSnapshotPublisherFactory(core),
      setBadge: setBadge,
      badgeEnabled: prefs.badgeEnabled,
      isSetupCompleted: prefs.setupCompleted,
      notificationAuthorizationStatusProvider: notificationAuthorizationStatusProvider,
      selectedTab: selectedTab,
      todayString: todayString,
      now: now,
      defaults: prefs.defaults,
      cloudSyncMode: cloudSyncMode,
      cloudSyncSubscriber: CloudSyncFactory.makeSubscriber(
        mode: cloudSyncMode,
        containerIdentifier: containerID
      ),
      cloudSyncCoordinator: cloudSyncMode == .live ? cloudDataMaintenanceCoordinator : nil,
      cloudDataMaintenanceCoordinator: cloudDataMaintenanceCoordinator,
      cloudSyncServiceFactory: { mode in
        MobileCloudSyncServices(
          subscriber: CloudSyncFactory.makeSubscriber(
            mode: mode,
            containerIdentifier: containerID
          ),
          coordinator: mode == .live ? cloudDataMaintenanceCoordinator : nil
        )
      },
      eventKitCoordinator: Self.makeEventKitCoordinator(
        core: core,
        defaults: prefs.defaults
      ),
      eventKitEnabled: prefs.eventKitEnabled,
      eventKitCalendarFilterMode: prefs.eventKitCalendarFilterMode,
      eventKitIncludedCalendarIDs: prefs.eventKitIncludedCalendarIDs,
      eventKitExcludedCalendarIDs: prefs.eventKitExcludedCalendarIDs
    )
  }

  @MainActor
  private static func makeEventKitCoordinator(
    core: any LorvexCoreServicing,
    defaults: UserDefaults
  ) -> (any MobileEventKitCoordinating)? {
    #if canImport(EventKit)
      let calendarIDKey = "eventKit.lorvexCalendarID"
      let latchKey = "eventKit.calendarAccessGranted"
      let defaultsBox = MobileSendableUserDefaults(defaults)
      let access = MobileLiveEventKitAccess(
        loadCalendarID: { defaultsBox.string(forKey: calendarIDKey) },
        loadConfirmedReadAccess: { defaultsBox.bool(forKey: latchKey) },
        saveConfirmedReadAccess: { defaultsBox.set($0, forKey: latchKey) }
      )
      return MobileEventKitCoordinator.make(core: core, access: access)
    #else
      return nil
    #endif
  }
}

private final class MobileSendableUserDefaults: @unchecked Sendable {
  private let defaults: UserDefaults

  init(_ defaults: UserDefaults) {
    self.defaults = defaults
  }

  func string(forKey key: String) -> String? {
    defaults.string(forKey: key)
  }

  func bool(forKey key: String) -> Bool {
    defaults.bool(forKey: key)
  }

  func set(_ value: Bool, forKey key: String) {
    defaults.set(value, forKey: key)
  }
}
