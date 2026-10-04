import SwiftUI

struct MobileStoreCreateListSheet: View {
  @Bindable var store: MobileStore
  @Binding var isPresented: Bool

  var body: some View {
    NavigationStack {
      Form {
        Section {
          MobileListSheetHeader(
            store: store, idPrefix: "mobileCreateList", focusesNameOnAppear: true, submit: submit)
        }
      }
      .mobileSheetTitle(
        String(
          localized: "sheet.new_list", defaultValue: "New List", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(
            String(
              localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
              bundle: MobileL10n.bundle)
          ) {
            isPresented = false
          }
          .accessibilityIdentifier("mobileCreateList.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            submit()
          } label: {
            if store.isCreatingList {
              ProgressView().tint(.white)
            } else {
              Text(
                String(
                  localized: "common.create", defaultValue: "Create", table: "Localizable",
                  bundle: MobileL10n.bundle))
            }
          }
          .mobileProminentToolbarButtonStyle()
          .disabled(!store.canCreateListDraft)
          .accessibilityIdentifier("mobileCreateList.confirm")
        }
      }
    }
    // List editor detents: medium + large for quick naming or full descriptions.
    .mobileCompactEditorSheetPresentation()
    .onAppear { store.beginCreateListDraft() }
  }

  private func submit() {
    Task {
      let created = await store.createDraftList()
      if created {
        isPresented = false
      }
    }
  }
}
