import AppIntents
import Foundation
import LorvexCore
import LorvexWidgetIntents
import Testing

@testable import LorvexWidgetExtension

// MARK: - Control widget

@MainActor
@Test
func lorvexCaptureControlWidgetIsInstantiable() {
  let widget = LorvexCaptureControlWidget()
  _ = widget
}

/// Control Center identifies a control by its kind, so the two Lorvex controls
/// must never share one.
@MainActor
@Test
func lorvexCaptureControlWidgetKindIsItsOwn() {
  #expect(LorvexCaptureControlWidget.kind == "com.lorvex.control.capture")
  #expect(LorvexCaptureControlWidget.kind != LorvexTodayControlWidget.kind)
}

// MARK: - Intent

/// AppIntents constructs the control's intent through a zero-argument `init()`.
@Test
func openLorvexCaptureIntentIsDefaultConstructible() {
  let intent = OpenLorvexCaptureIntent()
  _ = intent
}

/// Performing the control intent records a Quick Capture request in the handoff
/// store, replacing any navigation request an earlier tap left behind, so the
/// app presents the capture sheet and nothing else.
@Test
func openLorvexCaptureIntentStoresQuickCaptureHandoff() async throws {
  let suiteName = "OpenLorvexCaptureIntentTests.\(UUID().uuidString)"
  defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
  try await LorvexIntentHandoffStore.withScopedSuiteName(suiteName) {
    let handoffStore = LorvexIntentHandoffStore()
    handoffStore.clear()
    handoffStore.storeDestination(SidebarSelection.calendar.rawValue)

    let intent = OpenLorvexCaptureIntent()
    _ = try await intent.perform()

    #expect(handoffStore.consumeDestination() == nil)
    #expect(handoffStore.consumeQuickAction() == .quickCapture)
  }
}
