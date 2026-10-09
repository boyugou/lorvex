import LorvexCore
import SwiftUI

/// Confirmation sheet for the destructive Settings actions (erasing this
/// device's data, deleting the Lorvex iCloud data).
///
/// The friction is the consequence statement plus a destructive-role button the
/// user has to aim at, which is how the system's own irreversible actions
/// confirm. Store-agnostic (plain data in, one callback out), hence the
/// `Mobile` — not `MobileStore` — prefix. It opens at half height, and at
/// full height at accessibility text sizes, where the statement and the button
/// under it would not both fit in half of the screen.
struct MobileDestructiveConfirmationSheet: View {
  let title: String
  let message: String
  /// Destructive button title.
  let confirmTitle: String
  /// Dot-separated prefix for the sheet's accessibility identifiers
  /// (`<prefix>.confirm`, `<prefix>.cancel`).
  let accessibilityIdentifierPrefix: String
  let onConfirm: () -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(message)
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
        }

        Section {
          Button(role: .destructive) {
            dismiss()
            onConfirm()
          } label: {
            Text(confirmTitle)
              .frame(maxWidth: .infinity)
          }
          .accessibilityIdentifier("\(accessibilityIdentifierPrefix).confirm")
        }
      }
      .mobileSheetTitle(title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(
            String(
              localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
              bundle: MobileL10n.bundle)
          ) {
            dismiss()
          }
          .accessibilityIdentifier("\(accessibilityIdentifierPrefix).cancel")
        }
      }
    }
    .mobileSystemContentMargins()
    .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium])
  }
}
