import LorvexCore
import SwiftUI

/// Type-to-confirm modal for the destructive Settings actions ("Reset This
/// Device", "Delete iCloud Data"). A plain confirmation dialog is too easy to
/// click through for actions this irreversible, so the destructive button
/// stays disabled until the user types the action-specific confirmation word —
/// distinct words per action, so muscle memory from one can never confirm the
/// other.
///
/// The word match is case-insensitive and whitespace-tolerant: the friction is
/// deliberateness, not typing precision.
struct SettingsTypedConfirmationSheet: View {
  let title: String
  let message: String
  /// The word the user must type, shown in the prompt (localized per language).
  let confirmationWord: String
  /// Destructive button title.
  let confirmTitle: String
  /// SF Symbol shown beside the title.
  let systemImage: String
  /// Dot-separated prefix for the sheet's accessibility identifiers
  /// (`<prefix>.field`, `<prefix>.confirm`, `<prefix>.cancel`).
  let accessibilityIdentifierPrefix: String
  let onConfirm: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var typedWord = ""
  @FocusState private var fieldFocused: Bool

  private var wordMatches: Bool {
    typedWord
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .compare(confirmationWord, options: [.caseInsensitive]) == .orderedSame
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: systemImage)
          .font(.system(size: 28, weight: .medium))
          .foregroundStyle(.red)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 6) {
          Text(title)
            .font(LorvexDesign.Typography.primaryEmphasis)
            .fixedSize(horizontal: false, vertical: true)
          Text(message)
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        Text(
          String(
            format: String(
              localized: "settings.destructive.confirm.prompt",
              defaultValue: "Type “%@” to confirm.",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            ),
            confirmationWord)
        )
        .font(LorvexDesign.Typography.secondaryText)

        TextField(confirmationWord, text: $typedWord)
          .textFieldStyle(.roundedBorder)
          .autocorrectionDisabled()
          .focused($fieldFocused)
          .onSubmit {
            if wordMatches {
              dismiss()
              onConfirm()
            }
          }
          .accessibilityIdentifier("\(accessibilityIdentifierPrefix).field")
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
        .tint(.red)
        .disabled(!wordMatches)
        .accessibilityIdentifier("\(accessibilityIdentifierPrefix).confirm")
      }
    }
    .padding(20)
    .frame(width: 440)
    .onAppear { fieldFocused = true }
  }
}
