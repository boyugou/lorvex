import LorvexCore
import SwiftUI

/// New List: the list's icon, name, and description in the sheet's header,
/// above Cancel / Create (``CreationSheetLayout``).
struct CreateListSheet: View {
  @Bindable var store: AppStore
  @Binding var isPresented: Bool

  var body: some View {
    CreationSheetLayout(title: String(localized: "lists.sheet.create.title", defaultValue: "New List", table: "Localizable", bundle: LorvexL10n.bundle)) {
      ListSheetHeader(store: store, idPrefix: "createList")
    } footer: {
      DraftSheetFooter(
        idPrefix: "createList",
        confirmTitle: String(localized: "lists.sheet.create.confirm", defaultValue: "Create", table: "Localizable", bundle: LorvexL10n.bundle),
        confirmAccessibilityLabel: String(localized: "lists.create.a11y", defaultValue: "Create List", table: "Localizable", bundle: LorvexL10n.bundle),
        isConfirmDisabled: store.isCreating
          || store.draftListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        cancel: { isPresented = false }
      ) {
        Task {
          await store.createDraftList()
          if store.errorMessage == nil {
            isPresented = false
          }
        }
      }
    }
    .onAppear { store.beginCreateListDraft() }
  }
}
