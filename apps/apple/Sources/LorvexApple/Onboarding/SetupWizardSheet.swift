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

  @State private var wizardState = SetupWizardState()

  var body: some View {
    VStack(spacing: 0) {
      stepIndicator
        .padding(.top, 20)

      currentStepView
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .reduceMotionAnimation(.easeInOut, value: wizardState.currentStep)
    }
    .frame(width: 540, height: 480)
  }

  @ViewBuilder
  private var currentStepView: some View {
    switch wizardState.currentStep {
    case .welcome:
      WelcomeStep(onNext: advance)
    case .permissions:
      PermissionsStep(store: store, settings: settings, wizardState: wizardState, onNext: advance)
    case .done:
      DoneStep(settings: settings, wizardState: wizardState, onDone: onDismiss)
    }
  }

  private var stepIndicator: some View {
    HStack(spacing: 8) {
      ForEach(SetupWizardStep.allCases, id: \.self) { step in
        Circle()
          .fill(step.rawValue <= wizardState.currentStep.rawValue ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.3)))
          .frame(width: 8, height: 8)
          .reduceMotionAnimation(.easeInOut, value: wizardState.currentStep)
      }
    }
  }

  private func advance() {
    lorvexAnimated(.default) { wizardState.advance() }
  }
}
