import LorvexCore
import SwiftUI

// MARK: - iCloud Sync

/// The iCloud sync page. Sync is off until someone turns it on; Turn On does
/// what the Settings picker does (sync starts at once), and Not Now leaves
/// sync off. Its points answer what a person weighs before turning it on:
/// what it does, where the data lives, and whether the choice is final.
struct CloudSyncStep: View {
  let store: AppStore
  let settings: AppSettingsStore
  let onNext: () -> Void
  let onSync: () -> Void

  var body: some View {
    SetupWizardPage(
      systemImage: "icloud",
      title: LocalizedStringResource("setup.sync.title", defaultValue: "Sync with iCloud", table: "Localizable", bundle: LorvexL10n.bundle)
    ) {
      SetupWizardFeatureList {
        SetupWizardFeatureRow(
          systemImage: "laptopcomputer.and.iphone",
          title: LocalizedStringResource("setup.sync.devices.title", defaultValue: "The same on every device", table: "Localizable", bundle: LorvexL10n.bundle),
          detail: LocalizedStringResource("setup.sync.devices.detail", defaultValue: "Your tasks, lists, and habits stay in step on your Mac, iPhone, and iPad.", table: "Localizable", bundle: LorvexL10n.bundle))
        SetupWizardFeatureRow(
          systemImage: "lock.icloud",
          title: LocalizedStringResource("setup.sync.private.title", defaultValue: "Private to you", table: "Localizable", bundle: LorvexL10n.bundle),
          detail: LocalizedStringResource("setup.sync.private.detail", defaultValue: "Stored encrypted in your own iCloud account. Lorvex has no server of its own.", table: "Localizable", bundle: LorvexL10n.bundle))
        SetupWizardFeatureRow(
          systemImage: "switch.2",
          title: LocalizedStringResource("setup.sync.off.title", defaultValue: "Off whenever you like", table: "Localizable", bundle: LorvexL10n.bundle),
          detail: LocalizedStringResource("setup.sync.off.detail", defaultValue: "Turn syncing off anytime in Settings. Your data stays on this Mac.", table: "Localizable", bundle: LorvexL10n.bundle))
      }
    } actions: {
      Button(String(localized: "setup.not_now", defaultValue: "Not Now", table: "Localizable", bundle: LorvexL10n.bundle), action: onNext)
        .accessibilityIdentifier("setup.sync.notNow")
      SetupWizardPrimaryButton(String(localized: "setup.sync.turn_on", defaultValue: "Turn On iCloud Sync", table: "Localizable", bundle: LorvexL10n.bundle)) {
        store.turnOnCloudSync(settings: settings)
        onSync()
      }
      .accessibilityIdentifier("setup.sync.turnOn")
    }
  }
}

// MARK: - Done

/// The last page names the two ways work gets into Lorvex. Get Started
/// closes setup; Connect an Assistant closes it and opens Settings on the
/// Assistant category, where a client is connected.
struct DoneStep: View {
  let store: AppStore
  let settings: AppSettingsStore
  let wizardState: SetupWizardState
  let onDone: () -> Void

  @Environment(\.openSettings) private var openSettings

  var body: some View {
    SetupWizardPage(
      systemImage: "checkmark.seal.fill",
      iconTint: LorvexDesign.Palette.success,
      title: LocalizedStringResource("setup.done.title", defaultValue: "You’re ready.", table: "Localizable", bundle: LorvexL10n.bundle)
    ) {
      SetupWizardFeatureList {
        SetupWizardFeatureRow(
          systemImage: "plus.circle",
          title: LocalizedStringResource("setup.done.capture.title", defaultValue: "Capture it yourself", table: "Localizable", bundle: LorvexL10n.bundle),
          detail: LocalizedStringResource("setup.done.capture.detail", defaultValue: "Press ⌘N anywhere in Lorvex to add a task.", table: "Localizable", bundle: LorvexL10n.bundle))
        SetupWizardFeatureRow(
          systemImage: "sparkles",
          title: LocalizedStringResource("setup.done.assistant.title", defaultValue: "Or let your assistant add it", table: "Localizable", bundle: LorvexL10n.bundle),
          detail: LocalizedStringResource("setup.done.assistant.detail", defaultValue: "Connect Claude or another assistant in Settings under Assistant, and it adds tasks and plans your day with you.", table: "Localizable", bundle: LorvexL10n.bundle))
      }
    } actions: {
      Button(String(localized: "setup.done.connect_assistant", defaultValue: "Connect an Assistant…", table: "Localizable", bundle: LorvexL10n.bundle)) {
        finish()
        store.requestedSettingsCategory = .mcpHost
        openSettings()
      }
      .accessibilityIdentifier("setup.done.connectAssistant")
      SetupWizardPrimaryButton(String(localized: "setup.done.get_started", defaultValue: "Get Started", table: "Localizable", bundle: LorvexL10n.bundle), action: finish)
    }
  }

  private func finish() {
    wizardState.complete(settings: settings)
    onDone()
  }
}
