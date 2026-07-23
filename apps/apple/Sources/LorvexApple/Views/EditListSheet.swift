import LorvexCore
import SwiftUI

struct EditListSheet: View {
  let list: LorvexList
  @Bindable var store: AppStore
  @Binding var isPresented: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      header

      ListFormFields(store: store, idPrefix: "editList")

      DraftSheetFooter(
        idPrefix: "editList",
        confirmTitle: String(localized: "common.save", defaultValue: "Save", table: "Localizable", bundle: LorvexL10n.bundle),
        confirmAccessibilityLabel: String(localized: "lists.sheet.edit.save_a11y", defaultValue: "Save list", table: "Localizable", bundle: LorvexL10n.bundle),
        isConfirmDisabled: store.isCreating
          || store.draftListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        cancel: { isPresented = false }
      ) {
        Task {
          await store.updateList(list)
          if store.errorMessage == nil {
            isPresented = false
          }
        }
      }
    }
    .padding(20)
    .frame(minWidth: 400, idealWidth: 440)
  }

  private var header: some View {
    DraftSheetHeader(
      title: String(localized: "lists.sheet.edit.title", defaultValue: "Edit List", table: "Localizable", bundle: LorvexL10n.bundle),
      subtitle: String(
        localized: "lists.sheet.edit.description",
        defaultValue: "Tune the name and description shown in the sidebar.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      systemImage: "folder"
    )
  }
}
