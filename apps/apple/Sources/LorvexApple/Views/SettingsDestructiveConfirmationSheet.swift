import LorvexCore
import SwiftUI

/// Confirmation modal for the destructive Settings actions ("Reset This
/// Device", "Delete iCloud Data").
///
/// The friction is the consequence statement plus a destructive-role button the
/// user has to aim at, which is how the system's own irreversible actions
/// confirm. Cancel owns the Escape key, so the reflex dismissal is the safe one.
struct SettingsDestructiveConfirmationSheet: View {
  let title: String
  let message: String
  /// Destructive button title.
  let confirmTitle: String
  /// SF Symbol shown beside the title.
  let systemImage: String
  /// Dot-separated prefix for the sheet's accessibility identifiers
  /// (`<prefix>.confirm`, `<prefix>.cancel`).
  let accessibilityIdentifierPrefix: String
  let onConfirm: () -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: systemImage)
          .font(LorvexDesign.Typography.screenTitle.weight(.medium))
          .foregroundStyle(LorvexDesign.Palette.destructive)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.sm) {
          Text(title)
            .font(LorvexDesign.Typography.primaryEmphasis)
            .fixedSize(horizontal: false, vertical: true)
          Text(message)
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      HStack {
        Spacer()
        Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: LorvexL10n.bundle)) {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("\(accessibilityIdentifierPrefix).cancel")

        Button(role: .destructive) {
          dismiss()
          onConfirm()
        } label: {
          Text(confirmTitle)
        }
        .buttonStyle(.borderedProminent)
        .tint(LorvexDesign.Palette.destructive)
        .accessibilityIdentifier("\(accessibilityIdentifierPrefix).confirm")
      }
    }
    .padding(20)
    .frame(width: 440)
  }
}
