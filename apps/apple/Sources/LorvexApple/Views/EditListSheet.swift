import LorvexCore
import SwiftUI

/// Edit List: the list's icon, name, and description in the sheet's header,
/// above Cancel / Save (``CreationSheetLayout``).
struct EditListSheet: View {
  let list: LorvexList
  @Bindable var store: AppStore
  @Binding var isPresented: Bool

  var body: some View {
    CreationSheetLayout(title: String(localized: "lists.sheet.edit.title", defaultValue: "Edit List", table: "Localizable", bundle: LorvexL10n.bundle)) {
      ListSheetHeader(store: store, idPrefix: "editList")
    } footer: {
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
  }
}
