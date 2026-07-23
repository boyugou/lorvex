import AppIntents
import Foundation
import LorvexCore
import LorvexSystemIntents
import LorvexWidgetIntents
import Testing

@testable import LorvexSystemIntents
@testable import LorvexWidgetIntents

// Guards the App Intents security pass: every perform-style intent runs over the
// real CloudKit-synced store, so its lock-screen posture (`authenticationPolicy`),
// destructive-action confirmation, and execution mode are load-bearing. These
// tests pin the central classification so a new intent added as a bare
// `AppIntent` — or filed under the wrong tier — fails here instead of silently
// shipping as `.alwaysAllowed`.

// MARK: - F17: authentication policy per capability

@Test
func navigationAndCaptureIntentsAreAlwaysAllowed() {
  #expect(OpenLorvexIntent.authenticationPolicy == .alwaysAllowed)
  #expect(OpenLorvexTaskIntent.authenticationPolicy == .alwaysAllowed)
  #expect(CaptureLorvexTaskIntent.authenticationPolicy == .alwaysAllowed)
  // Focus-filter setup is system-invoked on Focus activation, possibly locked.
  #expect(LorvexFocusFilterIntent.authenticationPolicy == .alwaysAllowed)
}

@Test
func contentReadAndExportIntentsRequireLocalDeviceAuthentication() {
  let localAuth: [any AppIntent.Type] = [
    ExportLorvexDataIntent.self,
    ExportLorvexCalendarICSIntent.self,
    ReadLorvexMemoryIntent.self,
    ReadLorvexReviewHistoryIntent.self,
    ReadLorvexWeeklyReviewIntent.self,
    ReadLorvexRecentLogsIntent.self,
    ReadLorvexRuntimeDiagnosticsIntent.self,
    ReadLorvexSessionContextIntent.self,
    ReadLorvexTaskIntent.self,
    ReadLorvexOverviewIntent.self,
    ReadLorvexPreferenceIntent.self,
    ReadLorvexPreferencesIntent.self,
    ReadLorvexCalendarTimelineIntent.self,
    ReadLorvexUpcomingTasksIntent.self,
    ReadLorvexAIChangelogIntent.self,
    SearchLorvexTasksIntent.self,
    SearchLorvexCalendarEventsIntent.self,
  ]
  #expect(localAuth.count == 17)
  for type in localAuth {
    #expect(type.authenticationPolicy == .requiresLocalDeviceAuthentication, "\(type)")
  }
}

@Test
func destructiveAndMutatingIntentsRequireAuthentication() {
  let authenticated: [any AppIntent.Type] = [
    // Destructive
    DeleteLorvexMemoryIntent.self,
    DeleteLorvexListIntent.self,
    DeleteLorvexHabitIntent.self,
    DeleteLorvexHabitReminderPolicyIntent.self,
    DeleteLorvexCalendarEventIntent.self,
    DeleteLorvexPreferenceIntent.self,
    CancelLorvexTaskIntent.self,
    ResetLorvexHabitIntent.self,
    ClearLorvexCurrentFocusIntent.self,
    RemoveLorvexChecklistItemIntent.self,
    RemoveLorvexTaskReminderIntent.self,
    RemoveLorvexTaskRecurrenceIntent.self,
    RemoveLorvexTaskRecurrenceExceptionIntent.self,
    RemoveLorvexTaskFromFocusIntent.self,
    // Batch / broad writes
    BatchCompleteLorvexTasksIntent.self,
    BatchCreateLorvexTasksIntent.self,
    BatchDeferLorvexTasksIntent.self,
    BatchMoveLorvexTasksIntent.self,
    BatchReopenLorvexTasksIntent.self,
    BatchCompleteLorvexHabitsIntent.self,
    UpdateLorvexTaskIntent.self,
    UpdateLorvexListIntent.self,
    UpdateLorvexCalendarEventIntent.self,
    SetLorvexTaskRecurrenceIntent.self,
    SetLorvexTaskRemindersIntent.self,
    SetLorvexPreferenceIntent.self,
    // Non-destructive writes
    CreateLorvexListIntent.self,
    CreateLorvexHabitIntent.self,
    CompleteLorvexTaskIntent.self,
    DeferLorvexTaskIntent.self,
    SaveLorvexMemoryIntent.self,
    // Metadata / non-content reads
    ReadLorvexListsIntent.self,
    ListLorvexTasksIntent.self,
    ReadLorvexSyncStatusIntent.self,
    ReadLorvexGuideIntent.self,
    ReadLorvexCurrentFocusIntent.self,
  ]
  for type in authenticated {
    #expect(type.authenticationPolicy == .requiresAuthentication, "\(type)")
  }
}

@Test
func classifiedIntentsRouteThroughCentralSecurityMarkers() {
  // Typed as `any AppIntent.Type` so each `is` is a genuine runtime check:
  // every classified intent conforms to the root marker and therefore cannot be
  // a bare `AppIntent` that would silently inherit `.alwaysAllowed`.
  let classified: [any AppIntent.Type] = [
    OpenLorvexIntent.self,
    CaptureLorvexTaskIntent.self,
    DeleteLorvexMemoryIntent.self,
    CancelLorvexTaskIntent.self,
    ReadLorvexOverviewIntent.self,
    ExportLorvexDataIntent.self,
    SearchLorvexTasksIntent.self,
    UpdateLorvexTaskIntent.self,
  ]
  for type in classified {
    #expect(type is any LorvexSecuredIntent.Type, "\(type)")
  }
  // Tier separation, on existential metatypes so the checks are not folded away.
  let overview: any AppIntent.Type = ReadLorvexOverviewIntent.self
  #expect(overview is any LorvexLocalAuthIntent.Type)
  #expect(!(overview is any LorvexUnauthenticatedIntent.Type))
  let delete: any AppIntent.Type = DeleteLorvexMemoryIntent.self
  #expect(delete is any LorvexAuthenticatedIntent.Type)
  #expect(!(delete is any LorvexUnauthenticatedIntent.Type))
}

// MARK: - F19: destructive intents confirm before mutating

@Test
func destructiveIntentRequestsConfirmationBeforeMutating() async throws {
  try await withIsolatedAppIntentDatabase {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    _ = try await core.setPreference(key: "theme", value: "\"system\"")

    // No system context supplies confirmation in a unit test, so `perform()`
    // throws at the confirmation request — which only fires if it precedes the
    // runner mutation.
    await #expect(throws: (any Error).self) {
      _ = try await DeleteLorvexPreferenceIntent(key: "theme").perform()
    }

    // The mutation never ran: the seeded preference survives the aborted delete.
    let survivor = try await core.getPreference(key: "theme")
    #expect(survivor != nil)
  }
}

// MARK: - F21: openAppWhenRun migrates to supportedModes

@Test
func executionModesSplitNavigationForegroundFromBackground() {
  #expect(OpenLorvexIntent.openAppWhenRun == true)
  #expect(OpenLorvexTaskIntent.openAppWhenRun == true)
  #expect(DeleteLorvexMemoryIntent.openAppWhenRun == false)
  #expect(ReadLorvexOverviewIntent.openAppWhenRun == false)
  #expect(CaptureLorvexTaskIntent.openAppWhenRun == false)

  if #available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *) {
    #expect(OpenLorvexIntent.supportedModes == .foreground)
    #expect(OpenLorvexTaskIntent.supportedModes == .foreground)
    #expect(DeleteLorvexMemoryIntent.supportedModes == .background)
    #expect(ReadLorvexOverviewIntent.supportedModes == .background)
    #expect(CaptureLorvexTaskIntent.supportedModes == .background)
  }
}

// MARK: - Widget-tap intents: undiscoverable, attended, background

@Test
func widgetActionIntentsAreUndiscoverableAndAlwaysAllowed() {
  let widgetActions: [any AppIntent.Type] = [
    WidgetCompleteTaskIntent.self,
    WidgetCompleteHabitIntent.self,
    WidgetDeferTaskIntent.self,
  ]
  for type in widgetActions {
    #expect(type.isDiscoverable == false, "\(type)")
    #expect(type.authenticationPolicy == .alwaysAllowed, "\(type)")
    #expect(type.openAppWhenRun == false, "\(type)")
  }
}

@Test
func focusControlIntentOpensForegroundWithoutAuthentication() {
  if #available(iOS 18.0, macOS 26.0, *) {
    #expect(OpenLorvexFocusIntent.authenticationPolicy == .alwaysAllowed)
    #expect(OpenLorvexFocusIntent.openAppWhenRun == true)
  }
  if #available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *) {
    #expect(OpenLorvexFocusIntent.supportedModes == .foreground)
  }
}
