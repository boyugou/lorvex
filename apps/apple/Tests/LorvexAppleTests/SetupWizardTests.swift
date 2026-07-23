import Foundation
import Testing

@testable import LorvexApple

@MainActor
@Suite("SetupWizardState")
struct SetupWizardTests {

  // MARK: - Step progression

  @Test("starts on the welcome step")
  func startsOnWelcomeStep() {
    let state = SetupWizardState()
    #expect(state.currentStep == .welcome)
  }

  @Test("advance moves through all steps in order")
  func advancesThroughAllSteps() {
    let state = SetupWizardState()
    let expected: [SetupWizardStep] = [.permissions, .done]
    for step in expected {
      state.advance()
      #expect(state.currentStep == step)
    }
  }

  @Test("advance does not move past the done step")
  func doesNotAdvancePastDone() {
    let state = SetupWizardState()
    // Advance to the last step.
    for _ in SetupWizardStep.allCases { state.advance() }
    #expect(state.currentStep == .done)
    // Calling advance again must be a no-op.
    state.advance()
    #expect(state.currentStep == .done)
  }

  // MARK: - Permission skipping

  @Test("skipping a permission marks it as not granted")
  func skippingPermissionAllowsCompletion() {
    let state = SetupWizardState()

    state.skipCalendar()
    state.skipNotifications()

    #expect(state.calendarPermissionState == .skipped)
    #expect(state.notificationsPermissionState == .skipped)
  }

  @Test("permissions are idle before any decision")
  func permissionsStartIdle() {
    let state = SetupWizardState()
    #expect(state.calendarPermissionState == .idle)
    #expect(state.notificationsPermissionState == .idle)
  }

  // MARK: - Completion

  @Test("completing wizard sets setupCompleted to true")
  func completeWritesSetupCompleted() {
    let suiteName = "test.SetupWizardTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettingsStore(defaults: defaults, environment: [:])
    let state = SetupWizardState()

    #expect(!settings.setupCompleted)
    state.complete(settings: settings)
    #expect(settings.setupCompleted)
  }

  @Test("setupCompleted persists across AppSettingsStore instances with the same defaults")
  func setupCompletedPersistsAcrossInstances() {
    let suiteName = "test.SetupWizardTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings1 = AppSettingsStore(defaults: defaults, environment: [:])

    let state = SetupWizardState()
    state.complete(settings: settings1)

    let settings2 = AppSettingsStore(defaults: defaults, environment: [:])
    #expect(settings2.setupCompleted)
  }
}
