import Foundation
import LorvexDomain
import Observation
import UserNotifications

/// Step sequence for the first-run setup wizard.
enum SetupWizardStep: Int, CaseIterable, Sendable {
  case welcome = 0
  case permissions
  case done
}

enum SetupPermissionState: Equatable, Sendable {
  case idle
  case requesting
  case granted
  case denied
  case skipped
}

/// View model for the first-run setup wizard.
///
/// Tracks the current step and permission outcomes. Calling `complete(settings:)`
/// persists `setupCompleted = true` to `AppSettingsStore`, preventing the wizard
/// from appearing on subsequent launches.
@MainActor
@Observable
final class SetupWizardState {
  var currentStep: SetupWizardStep = .welcome

  var calendarPermissionState: SetupPermissionState = .idle
  var notificationsPermissionState: SetupPermissionState = .idle

  func advance() {
    guard let next = SetupWizardStep(rawValue: currentStep.rawValue + 1) else { return }
    currentStep = next
  }

  func requestCalendarPermission(store: AppStore, settings: AppSettingsStore) async {
    calendarPermissionState = .requesting
    let granted = await store.requestCalendarAccessFromSettings()
    calendarPermissionState = granted ? .granted : .denied
    if granted {
      settings.eventKitEnabled = true
      await store.applyEventKitSettings(enabled: true)
    }
  }

  func requestNotificationsPermission() async {
    notificationsPermissionState = .requesting
    do {
      let granted = try await UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .sound, .badge])
      notificationsPermissionState = granted ? .granted : .denied
    } catch {
      notificationsPermissionState = .denied
    }
  }

  func skipCalendar() { calendarPermissionState = .skipped }
  func skipNotifications() { notificationsPermissionState = .skipped }

  /// Marks the wizard as complete and persists the flag to avoid future presentation.
  func complete(settings: AppSettingsStore) {
    settings.setupCompleted = true
  }
}
