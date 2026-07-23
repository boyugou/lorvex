import Foundation
import Testing
import UserNotifications

@testable import LorvexCore
@testable import LorvexMobile

/// Notification authorization status cases matching UNAuthorizationStatus,
/// with a convenience flag for denied-state recovery.
enum LorvexNotificationAuthorizationStatus: Equatable, Sendable {
  case notDetermined
  case denied
  case authorized
  case provisional
  case ephemeral

  /// True when the user has explicitly denied notifications and the app must
  /// direct them to System Settings to recover.
  var needsSettingsRecovery: Bool {
    self == .denied
  }

  /// True when notifications can be shown without further prompting.
  var isAuthorized: Bool {
    self == .authorized || self == .provisional || self == .ephemeral
  }
}

/// Queries and caches the current UNUserNotificationCenter authorization status.
///
/// Inject a custom `statusProvider` in tests — never pass the real
/// `UNUserNotificationCenter.current()` to avoid entitlement requirements.
struct LorvexNotificationAuthorization: Sendable {
  let statusProvider: @Sendable () async -> LorvexNotificationAuthorizationStatus

  init(
    statusProvider: @escaping @Sendable () async -> LorvexNotificationAuthorizationStatus =
      LorvexNotificationAuthorization.liveStatusProvider
  ) {
    self.statusProvider = statusProvider
  }

  /// Returns the current authorization status.
  func currentStatus() async -> LorvexNotificationAuthorizationStatus {
    await statusProvider()
  }

  /// True when the current status requires the user to open System Settings.
  func needsSettingsRecovery() async -> Bool {
    await currentStatus().needsSettingsRecovery
  }

  /// Live implementation that queries UNUserNotificationCenter.
  static let liveStatusProvider: @Sendable () async -> LorvexNotificationAuthorizationStatus = {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    switch settings.authorizationStatus {
    case .notDetermined: return .notDetermined
    case .denied: return .denied
    case .authorized: return .authorized
    case .provisional: return .provisional
    case .ephemeral: return .ephemeral
    @unknown default: return .notDetermined
    }
  }
}

// MARK: - Authorization status → needsSettingsRecovery

@Test
func authorizationStatusDeniedNeedsSettingsRecovery() {
  #expect(LorvexNotificationAuthorizationStatus.denied.needsSettingsRecovery == true)
}

@Test
func authorizationStatusAuthorizedDoesNotNeedSettingsRecovery() {
  #expect(LorvexNotificationAuthorizationStatus.authorized.needsSettingsRecovery == false)
}

@Test
func authorizationStatusNotDeterminedDoesNotNeedSettingsRecovery() {
  #expect(LorvexNotificationAuthorizationStatus.notDetermined.needsSettingsRecovery == false)
}

@Test
func authorizationStatusProvisionalIsAuthorized() {
  #expect(LorvexNotificationAuthorizationStatus.provisional.isAuthorized == true)
}

@Test
func authorizationStatusDeniedIsNotAuthorized() {
  #expect(LorvexNotificationAuthorizationStatus.denied.isAuthorized == false)
}

// MARK: - Authorization helper with injected provider

@Test
func notificationAuthorizationHelperReportsDenied() async {
  let auth = LorvexNotificationAuthorization(statusProvider: { .denied })
  let status = await auth.currentStatus()
  #expect(status == .denied)
  #expect(await auth.needsSettingsRecovery() == true)
}

@Test
func notificationAuthorizationHelperReportsAuthorized() async {
  let auth = LorvexNotificationAuthorization(statusProvider: { .authorized })
  #expect(await auth.needsSettingsRecovery() == false)
}

// MARK: - Badge count computation

@Test
func badgeCountCountsOverdueTasks() {
  let tasks = [
    makeTask(id: "a", dueDate: PlannedDayBridge.storageDate(forLocalInstant: Date(timeIntervalSinceNow: -86400)), status: .open),  // yesterday
    makeTask(id: "b", dueDate: PlannedDayBridge.storageDate(forLocalInstant: Date(timeIntervalSinceNow: 86400)), status: .open),   // tomorrow
    makeTask(id: "c", dueDate: PlannedDayBridge.storageDate(forLocalInstant: Date(timeIntervalSinceNow: -86400)), status: .completed), // done
  ]
  let today = ymdString(Date())
  let count = BadgeCoordinator.badgeCount(tasks: tasks, today: today)
  #expect(count == 1)
}

@Test
func badgeCountCountsDueTodayTasks() {
  let today = ymdString(Date())
  let tasks = [
    makeTask(id: "a", dueDate: PlannedDayBridge.storageDate(forLocalInstant: Date()), status: .open),
    makeTask(id: "b", dueDate: PlannedDayBridge.storageDate(forLocalInstant: Date()), status: .open),
  ]
  let count = BadgeCoordinator.badgeCount(tasks: tasks, today: today)
  #expect(count == 2)
}

@Test
func badgeCountExcludesFutureTasks() {
  let today = ymdString(Date())
  let tasks = [
    makeTask(id: "a", dueDate: PlannedDayBridge.storageDate(forLocalInstant: Date(timeIntervalSinceNow: 86400)), status: .open),
  ]
  let count = BadgeCoordinator.badgeCount(tasks: tasks, today: today)
  #expect(count == 0)
}

@Test
func badgeCountExcludesCompletedAndCancelled() {
  let today = ymdString(Date())
  let tasks = [
    makeTask(id: "a", dueDate: Date(timeIntervalSinceNow: -86400), status: .completed),
    makeTask(id: "b", dueDate: Date(timeIntervalSinceNow: -86400), status: .cancelled),
  ]
  let count = BadgeCoordinator.badgeCount(tasks: tasks, today: today)
  #expect(count == 0)
}

// MARK: - Badge coordinator applies correct count

@Test
func badgeCoordinatorCallsSetBadgeWithComputedCount() async {
  let counter = BadgeCounter()
  let today = ymdString(Date())
  let tasks = [
    makeTask(id: "a", dueDate: Date(timeIntervalSinceNow: -86400), status: .open),
  ]
  let coordinator = BadgeCoordinator(
    badgeEnabled: true,
    today: today,
    setBadge: { await counter.set($0) }
  )
  await coordinator.update(tasks: tasks)
  #expect(await counter.value == 1)
}

@Test
func badgeCoordinatorClearsBadgeWhenDisabled() async {
  let counter = BadgeCounter()
  let today = ymdString(Date())
  let tasks = [
    makeTask(id: "a", dueDate: Date(timeIntervalSinceNow: -86400), status: .open),
  ]
  let coordinator = BadgeCoordinator(
    badgeEnabled: false,
    today: today,
    setBadge: { await counter.set($0) }
  )
  await coordinator.update(tasks: tasks)
  #expect(await counter.value == 0)
}

private actor BadgeCounter {
  private(set) var value: Int?
  func set(_ count: Int) { value = count }
}

// MARK: - Notification category registration identifiers

@Test
func notificationCategoriesIncludeTaskReminder() {
  let categories = lorvexNotificationCategories()
  let ids = categories.map(\.identifier)
  #expect(ids.contains(LorvexNotificationCategory.taskReminder))
}

@Test
func taskReminderCategoryIncludesExpectedActions() {
  let categories = lorvexNotificationCategories()
  guard
    let taskCategory = categories.first(where: {
      $0.identifier == LorvexNotificationCategory.taskReminder
    })
  else {
    Issue.record("taskReminder category not found")
    return
  }
  let actionIDs = Set(taskCategory.actions.map(\.identifier))
  #expect(actionIDs.contains(LorvexNotificationActionID.completeTask))
  #expect(actionIDs.contains(LorvexNotificationActionID.deferTask))
  #expect(actionIDs.contains(LorvexNotificationActionID.snoozeTask))
}

// MARK: - Permissions view model exposes implemented mobile permissions

@Test
@MainActor
func permissionsViewModelInitializesWithUnknownStatus() {
  let vm = PermissionsStatusViewModel()
  #expect(vm.notificationsStatus == .unknown)
}

// MARK: - Helpers

private func makeTask(id: String, dueDate: Date?, status: LorvexTask.Status) -> LorvexTask {
  LorvexTask(
    id: id,
    title: "Task \(id)",
    notes: "",
    priority: .p2,
    status: status,
    dueDate: dueDate,
    estimatedMinutes: nil,
    tags: []
  )
}

private func ymdString(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = .current
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter.string(from: date)
}
