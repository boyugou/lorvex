import LorvexCore
import SwiftUI

/// The calm field panel shared by the create and edit list sheets.
struct ListFormFields: View {
  @Bindable var store: AppStore
  let idPrefix: String
  /// Claimed when the sheet appears so the user can type immediately.
  @FocusState private var nameFocused: Bool

  var body: some View {
    DraftSheetPanel(accessibilityIdentifier: "\(idPrefix).fields") {
      DraftSheetField(
        title: String(localized: "lists.sheet.field.name", defaultValue: "Name", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "text.cursor"
      ) {
        TextField(
          String(localized: "lists.sheet.field.name", defaultValue: "Name", table: "Localizable", bundle: LorvexL10n.bundle),
          text: $store.draftListName
        )
        .font(LorvexDesign.Typography.primaryText)
        .textFieldStyle(.plain)
        .focused($nameFocused)
        .accessibilityLabel(String(
          localized: "lists.sheet.field.name_a11y",
          defaultValue: "List name",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ))
        .accessibilityIdentifier("\(idPrefix).name")
      }

      DraftSheetField(
        title: String(localized: "lists.sheet.field.description", defaultValue: "Description", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "note.text"
      ) {
        LorvexPlainTextEditor(
          text: $store.draftListDescription,
          placeholder: String(localized: "lists.sheet.field.description", defaultValue: "Description", table: "Localizable", bundle: LorvexL10n.bundle),
          minHeight: 64,
          fontSize: 14
        )
        .accessibilityLabel(String(
          localized: "lists.sheet.field.description_a11y",
          defaultValue: "List description",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ))
        .accessibilityIdentifier("\(idPrefix).description")
      }

      LorvexIconColorField(
        icon: $store.draftListIcon,
        color: $store.draftListColor,
        idPrefix: idPrefix
      )
    }
    .task {
      nameFocused = false
      await Task.yield()
      nameFocused = true
    }
  }
}
