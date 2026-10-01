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
    .lorvexInsetPanel()
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
        .lorvexInsetPanel(padding: LorvexDesign.Spacing.s)
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
    .lorvexInsetPanel(padding: LorvexDesign.Spacing.s)
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

/// The layout a create or edit sheet shares: a small centered `title` naming
/// the action ("New List", "Edit Habit"), the thing being made below it
/// (``CreationSheetHeader``), its remaining fields as grouped form sections
/// (labels leading, controls trailing, explanations in section footers), and
/// the Cancel / confirm row. The form scrolls inside the sheet when its
/// sections outgrow the sheet's height. A sheet whose header holds every
/// field (``init(header:footer:)``) has no form: the header sits directly
/// above the buttons and the sheet hugs its content.
struct CreationSheetLayout<Header: View, Sections: View, Footer: View>: View {
  let title: String
  var height: CGFloat? = 560
  @ViewBuilder let header: () -> Header
  @ViewBuilder let sections: () -> Sections
  @ViewBuilder let footer: () -> Footer

  var body: some View {
    VStack(spacing: 0) {
      Text(title)
        .font(LorvexDesign.Typography.primaryEmphasis)
        .frame(maxWidth: .infinity)
        .padding(.top, LorvexDesign.Spacing.m)
        .accessibilityAddTraits(.isHeader)
      header()
        .padding(.horizontal, LorvexDesign.Spacing.l)
        .padding(.top, LorvexDesign.Spacing.m)
        .padding(.bottom, Sections.self == EmptyView.self ? LorvexDesign.Spacing.l : LorvexDesign.Spacing.xs)
      if Sections.self != EmptyView.self {
        Form {
          sections()
        }
        .formStyle(.grouped)
      }
      footer()
        .padding(.horizontal, LorvexDesign.Spacing.l)
        .padding(.bottom, LorvexDesign.Spacing.l)
    }
    .frame(width: 460, height: height)
  }
}

extension CreationSheetLayout where Sections == EmptyView {
  init(
    title: String, @ViewBuilder header: @escaping () -> Header, @ViewBuilder footer: @escaping () -> Footer
  ) {
    self.init(title: title, height: nil, header: header, sections: { EmptyView() }, footer: footer)
  }
}
