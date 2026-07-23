import LorvexCore
import SwiftUI

/// Type-to-confirm sheet for destructive Settings actions (deleting the Lorvex
/// iCloud data). A plain confirmation dialog is too easy to tap through for an
/// action this irreversible, so the destructive button stays disabled until
/// the user types the action-specific confirmation word.
///
/// Store-agnostic (plain data in, one callback out), hence the `Mobile` —
/// not `MobileStore` — prefix. The word match is case-insensitive and
/// whitespace-tolerant: the friction is deliberateness, not typing precision.
struct MobileTypedConfirmationSheet: View {
  let title: String
  let message: String
  /// The word the user must type, shown in the prompt (localized per language).
  let confirmationWord: String
  /// Destructive button title.
  let confirmTitle: String
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
    NavigationStack {
      Form {
        Section {
          Text(message)
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
        }

        Section {
          TextField(confirmationWord, text: $typedWord)
            .autocorrectionDisabled()
            #if os(iOS) || os(visionOS)
              .textInputAutocapitalization(.characters)
            #endif
            .focused($fieldFocused)
            .accessibilityIdentifier("\(accessibilityIdentifierPrefix).field")
        } footer: {
          Text(
            String(
              format: String(
                localized: "settings.sync.confirm.typed_prompt",
                defaultValue: "Type “%@” to confirm.", table: "Localizable",
                bundle: MobileL10n.bundle),
              confirmationWord))
        }

        Section {
          Button(role: .destructive) {
            dismiss()
            onConfirm()
          } label: {
            Text(confirmTitle)
              .frame(maxWidth: .infinity)
          }
          .disabled(!wordMatches)
          .accessibilityIdentifier("\(accessibilityIdentifierPrefix).confirm")
        }
      }
      .navigationTitle(title)
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
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
    .presentationDetents([.medium, .large])
    .onAppear { fieldFocused = true }
  }
}
