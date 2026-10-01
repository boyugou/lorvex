import LorvexCore
import SwiftUI

/// The top of the create and edit list sheets: the list's icon tile and name
/// (``CreationSheetHeader``), with its description typed on the lines under
/// the name. A list has no other fields, so this header is the whole form.
struct ListSheetHeader: View {
  @Bindable var store: AppStore
  let idPrefix: String

  var body: some View {
    CreationSheetHeader(
      icon: $store.draftListIcon,
      color: $store.draftListColor,
      name: $store.draftListName,
      defaultIcon: "list.bullet",
      namePrompt: String(
        localized: "lists.sheet.field.name_prompt", defaultValue: "List name", table: "Localizable",
        bundle: LorvexL10n.bundle),
      nameAccessibilityLabel: String(
        localized: "lists.sheet.field.name_a11y", defaultValue: "List name", table: "Localizable",
        bundle: LorvexL10n.bundle),
      idPrefix: idPrefix
    ) {
      TextField(
        String(
          localized: "lists.sheet.field.description_prompt", defaultValue: "Add a description",
          table: "Localizable", bundle: LorvexL10n.bundle),
        text: $store.draftListDescription,
        axis: .vertical
      )
      .lineLimit(1...3)
      .font(LorvexDesign.Typography.secondaryText)
      .foregroundStyle(.secondary)
      .textFieldStyle(.plain)
      .accessibilityLabel(String(
        localized: "lists.sheet.field.description_a11y", defaultValue: "List description",
        table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityIdentifier("\(idPrefix).description")
    }
  }
}
