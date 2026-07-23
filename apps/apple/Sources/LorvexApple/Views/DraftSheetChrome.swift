import LorvexCore
import SwiftUI

struct DraftSheetHeader: View {
  let title: String
  let subtitle: String
  let systemImage: String

  var body: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.s) {
      Image(systemName: systemImage)
        .font(LorvexDesign.Typography.primaryEmphasis)
        .foregroundStyle(.tint)
        .frame(width: 28, height: 28)
        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(LorvexDesign.Typography.primaryEmphasis)
        Text(subtitle)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
      }
    }
  }
}

struct DraftSheetPanel<Content: View>: View {
  let accessibilityIdentifier: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      content()
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.08), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    .overlay {
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
        .stroke(.separator.opacity(0.18), lineWidth: 0.5)
    }
    .accessibilityIdentifier(accessibilityIdentifier)
  }
}

struct DraftSheetField<Content: View>: View {
  let title: String
  let systemImage: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      Label(title, systemImage: systemImage)
        .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
        .foregroundStyle(.secondary)
      content()
        .padding(.horizontal, LorvexDesign.Spacing.s)
        .padding(.vertical, LorvexDesign.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    }
  }
}

struct DraftSheetControlRow<Content: View>: View {
  let title: String
  let systemImage: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Label(title, systemImage: systemImage)
        .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
        .foregroundStyle(.secondary)
      Spacer(minLength: LorvexDesign.Spacing.s)
      content()
    }
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
  }
}

/// The trailing Cancel / confirm button row shared by the draft sheets. Carries
/// the Escape (`.cancelAction`) and Return (`.defaultAction`) shortcuts and the
/// `<idPrefix>.cancel` / `<idPrefix>.confirm` accessibility identifiers, so each
/// sheet supplies only its confirm title, accessibility label, action, and the
/// confirm-disabled predicate.
struct DraftSheetFooter: View {
  let idPrefix: String
  let confirmTitle: String
  let confirmAccessibilityLabel: String
  let isConfirmDisabled: Bool
  let cancel: () -> Void
  let confirm: () -> Void

  var body: some View {
    HStack {
      Spacer()
      Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: LorvexL10n.bundle), action: cancel)
        .accessibilityLabel(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityIdentifier("\(idPrefix).cancel")
        .keyboardShortcut(.cancelAction)
      Button(confirmTitle, action: confirm)
        .accessibilityLabel(confirmAccessibilityLabel)
        .accessibilityIdentifier("\(idPrefix).confirm")
        .keyboardShortcut(.defaultAction)
        .disabled(isConfirmDisabled)
    }
  }
}
