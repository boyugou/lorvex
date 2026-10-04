import SwiftUI

/// The header of the New List and Edit List sheets: the list's icon tile and
/// name (``MobileCreationHeader``), with its description typed on the lines
/// under the name. A list has no other fields, so this header is the whole
/// form. `submit` runs when the description's Done key is pressed, and
/// `focusesNameOnAppear` puts the cursor in the name as the sheet opens, for a
/// sheet that starts a new list; identifiers are `<idPrefix>.name`,
/// `<idPrefix>.description`, and the tile's `<idPrefix>.appearance`.
struct MobileListSheetHeader: View {
  @Bindable var store: MobileStore
  let idPrefix: String
  var focusesNameOnAppear = false
  let submit: () -> Void
  @FocusState private var focusedField: Field?

  private enum Field {
    case name
    case description
  }

  var body: some View {
    MobileCreationHeader(
      icon: $store.listDraft.icon,
      color: $store.listDraft.color,
      fallbackIcon: "tray.fill",
      iconChoices: MobileIconChoices.list,
      idPrefix: idPrefix,
      willChooseAppearance: { focusedField = nil }
    ) {
      TextField(
        String(
          localized: "lists.sheet.field.name_prompt", defaultValue: "List name",
          table: "Localizable", bundle: MobileL10n.bundle),
        text: $store.listDraft.name,
        axis: .vertical
      )
      .lineLimit(1...)
      .focused($focusedField, equals: .name)
      .submitLabel(.next)
      .onSubmit { focusedField = .description }
      .accessibilityLabel(
        String(
          localized: "lists.field.name.a11y", defaultValue: "List name", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      .accessibilityIdentifier("\(idPrefix).name")
    } subtitle: {
      TextField(
        String(
          localized: "lists.sheet.field.description_prompt", defaultValue: "Add a description",
          table: "Localizable", bundle: MobileL10n.bundle),
        text: $store.listDraft.description,
        axis: .vertical
      )
      .lineLimit(1...)
      .focused($focusedField, equals: .description)
      .submitLabel(.done)
      .onSubmit(submit)
      .accessibilityLabel(
        String(
          localized: "lists.field.description.a11y", defaultValue: "List description",
          table: "Localizable", bundle: MobileL10n.bundle)
      )
      .accessibilityIdentifier("\(idPrefix).description")
    }
    .onAppear { if focusesNameOnAppear { focusedField = .name } }
  }
}
