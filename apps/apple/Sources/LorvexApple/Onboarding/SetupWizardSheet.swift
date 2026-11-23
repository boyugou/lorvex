import LorvexCore
import SwiftUI

/// Modal sheet that presents the first-run setup wizard.
///
/// Hosted via `.sheet(isPresented:)` bound to `!settings.setupCompleted`.
/// Steps advance only through the explicit Next buttons; the current step is
/// rendered via a manual `switch` rather than a `TabView` so macOS does not draw
/// a native tab-bar segmented control above the content.
struct SetupWizardSheet: View {
  let store: AppStore
  let settings: AppSettingsStore
  let onDismiss: () -> Void

  @State private var wizardState: SetupWizardState

  /// `wizardState` is the wizard's model, a fresh one by default; a caller
  /// that turns the pages itself (the DEBUG preview tour) passes its own.
  init(
    store: AppStore,
    settings: AppSettingsStore,
    wizardState: SetupWizardState = SetupWizardState(),
    onDismiss: @escaping () -> Void
  ) {
    self.store = store
    self.settings = settings
    self.onDismiss = onDismiss
    _wizardState = State(initialValue: wizardState)
  }

  var body: some View {
    VStack(spacing: 0) {
      if wizardState.currentStep != .welcome {
        stepIndicator.padding(.top, 20)
      }

      currentStepView
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .reduceMotionAnimation(LorvexDesign.Motion.page, value: wizardState.currentStep)
    }
    .frame(width: 540, height: wizardState.currentStep == .welcome ? 340 : 480)
  }

  @ViewBuilder
  private var currentStepView: some View {
    switch wizardState.currentStep {
    case .welcome:
      ScrollView {
        LorvexTodayTaskForm(welcome: .init(
          context: TodayCalmCopy.dateLine(logicalDay: store.logicalTodayDateString),
          sync: advance, skip: finish)
        ) { title in
          try await store.addTaskForToday(title)
          store.selection = .today
          finish()
        }
        .padding(32)
        .frame(maxWidth: 484)
      }
    case .cloudSync:
      CloudSyncStep(store: store, settings: settings, onNext: advance, onSync: finish)
    case .permissions:
      PermissionsStep(store: store, settings: settings, wizardState: wizardState, onNext: advance)
    case .done:
      DoneStep(store: store, settings: settings, wizardState: wizardState, onDone: onDismiss)
    }
  }

  private var stepIndicator: some View {
    HStack(spacing: 8) {
      ForEach(SetupWizardStep.allCases, id: \.self) { step in
        Circle()
          .fill(step.rawValue <= wizardState.currentStep.rawValue ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.3)))
          .frame(width: 8, height: 8)
          .reduceMotionAnimation(LorvexDesign.Motion.page, value: wizardState.currentStep)
      }
    }
  }

  private func finish() {
    wizardState.complete(settings: settings)
    onDismiss()
  }

  private func advance() {
    lorvexAnimated(LorvexDesign.Motion.page) { wizardState.advance() }
  }
}
