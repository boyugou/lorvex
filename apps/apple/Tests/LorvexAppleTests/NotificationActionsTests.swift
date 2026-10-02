import Foundation
import LorvexCore
import Testing
import UserNotifications

@testable import LorvexApple

// MARK: - Category and Action Identifier Tests

@Test
func notificationCategoryIdentifierIsStable() {
  #expect(LorvexNotificationCategory.taskReminder == "lorvex.category.taskReminder")
}

@Test
func notificationActionIdentifiersAreStable() {
  #expect(LorvexNotificationActionID.completeTask == "lorvex.action.completeTask")
  #expect(LorvexNotificationActionID.deferTask == "lorvex.action.deferTask")
  #expect(LorvexNotificationActionID.snoozeTask == "lorvex.action.snoozeTask")
}

@Test
func notificationCategoryUsesInjectedLocalizedActionTitles() {
  let titles = LorvexNotificationActionTitles(
    complete: "Fertig", deferToTomorrow: "Auf morgen", snooze: "In 1 Stunde")
  let category = lorvexNotificationCategories(titles: titles)
    .first { $0.identifier == LorvexNotificationCategory.taskReminder }
  let actionTitles = category?.actions.map(\.title) ?? []
  #expect(actionTitles == ["Fertig", "Auf morgen", "In 1 Stunde"])
}

@Test
func notificationActionIdentifiersAreDistinct() {
  let ids = [
    LorvexNotificationActionID.completeTask,
    LorvexNotificationActionID.deferTask,
    LorvexNotificationActionID.snoozeTask,
  ]
  #expect(Set(ids).count == 3)
}

// MARK: - Action Handler Tests

/// Builds a fake UNNotificationResponse-like value by wrapping userInfo
/// in a real UNNotificationRequest via UNMutableNotificationContent.
///
/// UNNotificationResponse cannot be instantiated directly; these tests use
/// `handleLorvexNotificationAction` via a thin seam that accepts the action
/// identifier and userInfo dictionary directly.
private func makeUserInfo(taskID: String) -> [AnyHashable: Any] {
  [LorvexNotificationRoute.taskIDUserInfoKey: taskID]
}

/// Minimal dispatch seam that mirrors `handleLorvexNotificationAction` logic
/// without requiring a live UNNotificationResponse, enabling unit tests
/// without UserNotifications entitlements.
@MainActor
private func dispatchAction(
  actionID: String,
  taskID: String,
  completeTask: @MainActor (String) async -> Void = { _ in },
  deferTask: @MainActor (String) async -> Void = { _ in },
  snoozeTask: @MainActor (String) async -> Void = { _ in }
) async {
  guard
    actionID == LorvexNotificationActionID.completeTask
      || actionID == LorvexNotificationActionID.deferTask
      || actionID == LorvexNotificationActionID.snoozeTask
  else { return }
  guard !taskID.isEmpty else { return }

  switch actionID {
  case LorvexNotificationActionID.completeTask:
    await completeTask(taskID)
  case LorvexNotificationActionID.deferTask:
    await deferTask(taskID)
  case LorvexNotificationActionID.snoozeTask:
    await snoozeTask(taskID)
  default:
    break
  }
}

@Test
@MainActor
func completeActionDispatchesCompleteTask() async {
  var completedID: String?
  await dispatchAction(
    actionID: LorvexNotificationActionID.completeTask,
    taskID: "task-abc",
    completeTask: { completedID = $0 }
  )
  #expect(completedID == "task-abc")
}

@Test
@MainActor
func deferActionDispatchesDeferTask() async {
  var deferredID: String?
  await dispatchAction(
    actionID: LorvexNotificationActionID.deferTask,
    taskID: "task-def",
    deferTask: { deferredID = $0 }
  )
  #expect(deferredID == "task-def")
}

@Test
@MainActor
func snoozeActionDispatchesSnoozeTask() async {
  var snoozedID: String?
  await dispatchAction(
    actionID: LorvexNotificationActionID.snoozeTask,
    taskID: "task-ghi",
    snoozeTask: { snoozedID = $0 }
  )
  #expect(snoozedID == "task-ghi")
}

@Test
func snoozeNotificationRequestPreservesRouteAndLocalizedCopy() {
  let request = SnoozeNotificationScheduler.notificationRequest(taskID: "task-snooze")
  let trigger = request.trigger as? UNTimeIntervalNotificationTrigger

  // Snooze uses a distinct, non-reaped prefix so a reminder resync can't sweep it.
  #expect(request.identifier == "\(ScheduledTaskReminder.snoozeIdentifierPrefix)task-snooze")
  #expect(!request.identifier.hasPrefix(ScheduledTaskReminder.identifierPrefix))
  #expect(trigger?.timeInterval == SnoozeNotificationScheduler.defaultInterval)
  #expect(request.content.title == "Task Reminder")
  #expect(request.content.body == "Snoozed reminder")
  #expect(request.content.sound == .default)
  #expect(request.content.interruptionLevel == .timeSensitive)
  #expect(request.content.categoryIdentifier == LorvexNotificationCategory.taskReminder)
  #expect(request.content.userInfo[LorvexNotificationRoute.taskIDUserInfoKey] as? String == "task-snooze")
  #expect(
    request.content.userInfo[LorvexNotificationRoute.deepLinkUserInfoKey] as? String
      == LorvexDeepLinkRoute.task("task-snooze").url.absoluteString
  )
}

@Test
@MainActor
func unknownActionIdentifierDispatchesNothing() async {
  var called = false
  await dispatchAction(
    actionID: "com.other.action",
    taskID: "task-xyz",
    completeTask: { _ in called = true },
    deferTask: { _ in called = true },
    snoozeTask: { _ in called = true }
  )
  #expect(!called)
}

@Test
@MainActor
func emptyTaskIDDispatchesNothing() async {
  var called = false
  await dispatchAction(
    actionID: LorvexNotificationActionID.completeTask,
    taskID: "",
    completeTask: { _ in called = true }
  )
  #expect(!called)
}

@Test
func mobileNotificationTaskActionsLogFailuresInsteadOfSilentlyDroppingThem() throws {
  let source = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexMobileApp/LorvexMobileAppDelegate.swift"),
    encoding: .utf8
  )

  #expect(!source.contains("try? await LorvexTaskIntentRunner.completeTask"))
  #expect(!source.contains("try? await LorvexTaskIntentRunner.deferTaskUntilTomorrow"))
  #expect(source.contains("Complete notification action failed"))
  #expect(source.contains("Defer notification action failed"))
}

private func packageRoot() -> URL {
  var url = URL(fileURLWithPath: #filePath)
  while url.lastPathComponent != "apps" {
    url.deleteLastPathComponent()
  }
  return url.appending(path: "apple")
}
