import LorvexCore
import SwiftUI

struct CreateListSheet: View {
  @Bindable var store: AppStore
  @Binding var isPresented: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      header

      ListFormFields(store: store, idPrefix: "createList")

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
    .padding(20)
    .frame(minWidth: 400, idealWidth: 440)
    .onAppear { store.beginCreateListDraft() }
  }

  private var header: some View {
    DraftSheetHeader(
      title: String(localized: "lists.sheet.create.title", defaultValue: "New List", table: "Localizable", bundle: LorvexL10n.bundle),
      subtitle: String(
        localized: "lists.sheet.create.description",
        defaultValue: "Create a user-owned scope for related tasks.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      systemImage: "folder.badge.plus"
    )
  }
}
