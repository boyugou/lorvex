import LorvexCore
import SwiftUI

// MARK: - Welcome

struct WelcomeStep: View {
  let onNext: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: "sparkles")
        .font(LorvexDesign.Typography.screenTitle)
        .foregroundStyle(.tint)
      Text(LocalizedStringResource("setup.welcome.title", defaultValue: "Welcome to Lorvex", table: "Localizable", bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.screenTitle)
      Text(LocalizedStringResource("setup.welcome.subtitle", defaultValue: "Lorvex is an AI-first planner — your assistant does most of the writing.", table: "Localizable", bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 380)
      Button(String(localized: "setup.action.continue", defaultValue: "Continue", table: "Localizable", bundle: LorvexL10n.bundle)) { onNext() }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
    .padding(40)
  }
}

// MARK: - Done

struct DoneStep: View {
  let settings: AppSettingsStore
  let wizardState: SetupWizardState
  let onDone: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: "checkmark.seal.fill")
        .font(LorvexDesign.Typography.screenTitle)
        .foregroundStyle(.green)
      Text(LocalizedStringResource("setup.done.title", defaultValue: "You're ready.", table: "Localizable", bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.screenTitle)
      Text(LocalizedStringResource("setup.done.subtitle", defaultValue: "Open Quick Capture with ⌘N to start capturing tasks.", table: "Localizable", bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 380)
      Button(String(localized: "setup.done.get_started", defaultValue: "Get Started", table: "Localizable", bundle: LorvexL10n.bundle)) {
        wizardState.complete(settings: settings)
        onDone()
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    }
    .padding(40)
  }
}
