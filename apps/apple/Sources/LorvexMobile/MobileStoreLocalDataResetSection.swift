import LorvexCore
import SwiftUI

/// Settings → Reset: erase this device's Lorvex data and return it to a
/// first-launch state. Sits at the bottom of Settings, where the system puts its
/// own erase actions, and states in the section footer that the iCloud copy is a
/// separate action so the choice is informed before the sheet even opens.
struct MobileStoreLocalDataResetSection: View {
  @Bindable var store: MobileStore
  @State private var showResetConfirmation = false
  @State private var resetInProgress = false
  @State private var resetErrorMessage: String?

  var body: some View {
    Section {
      // The in-flight spinner rides the trailing edge rather than replacing
      // the label, so the row keeps its title and its width while it works.
      Button(role: .destructive) {
        showResetConfirmation = true
      } label: {
        Label(
          String(
            localized: "settings.reset_device.title",
            defaultValue: "Erase This Device’s Data…",
            table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: "arrow.counterclockwise.circle")
      }
      .mobileDestructiveRowStyle()
      .disabled(
        resetInProgress || store.isLocalDataResetRunning || store.isSettingCloudSyncMode
          || store.isDataImportRunning || store.isCloudDataDeletionRunning)
      .overlay(alignment: .trailing) {
        if resetInProgress { ProgressView() }
      }
      .accessibilityIdentifier("mobileSettings.resetDevice")

      if let resetErrorMessage {
        Text(resetErrorMessage)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(LorvexDesign.Palette.error)
          .accessibilityIdentifier("mobileSettings.resetDevice.error")
      }
    } header: {
      Text(
        String(
          localized: "settings.section.reset_device", defaultValue: "Reset",
          table: "Localizable", bundle: MobileL10n.bundle))
    } footer: {
      Text(
        String(
          localized: "settings.reset_device.footer",
          defaultValue:
            "Erases all Lorvex data and settings on this device. It doesn’t touch iCloud — use Delete iCloud Data for that.",
          table: "Localizable", bundle: MobileL10n.bundle)
      )
      .accessibilityIdentifier("mobileSettings.resetDevice.footer")
    }
    .sheet(isPresented: $showResetConfirmation) {
      MobileDestructiveConfirmationSheet(
        title: String(
          localized: "settings.reset_device.confirm.title",
          defaultValue: "Erase this device’s data?", table: "Localizable",
          bundle: MobileL10n.bundle),
        message: String(
          localized: "settings.reset_device.confirm.message",
          defaultValue:
            "This permanently erases all Lorvex data and settings on this device. It doesn’t touch iCloud: if sync was on, your data stays in iCloud and can download again when sync is re-enabled. To remove the iCloud copy too, use Delete iCloud Data first.",
          table: "Localizable", bundle: MobileL10n.bundle),
        confirmTitle: String(
          localized: "settings.reset_device.confirm.action", defaultValue: "Erase This Device",
          table: "Localizable", bundle: MobileL10n.bundle),
        accessibilityIdentifierPrefix: "mobileSettings.resetDevice.confirm"
      ) {
        resetInProgress = true
        resetErrorMessage = nil
        Task {
          resetErrorMessage = await store.performLocalDataReset()
          resetInProgress = false
        }
      }
    }
  }
}
