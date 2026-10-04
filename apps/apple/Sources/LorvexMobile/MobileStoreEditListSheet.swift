import LorvexCore
import SwiftUI

struct MobileStoreEditListSheet: View {
  let list: LorvexList
  @Bindable var store: MobileStore
  @Binding var isPresented: Bool

  var body: some View {
    NavigationStack {
      Form {
        Section {
          MobileListSheetHeader(store: store, idPrefix: "mobileEditList", submit: submit)
        }
      }
      .mobileSheetTitle(
        String(
          localized: "sheet.edit_list", defaultValue: "Edit List", table: "Localizable",
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
          .accessibilityIdentifier("mobileEditList.cancel")
        }

        ToolbarItem(placement: .confirmationAction) {
          Button {
            submit()
          } label: {
            if store.isUpdatingList {
              ProgressView().tint(.white)
            } else {
              Text(
                String(
                  localized: "common.save", defaultValue: "Save", table: "Localizable",
                  bundle: MobileL10n.bundle))
            }
          }
          .mobileProminentToolbarButtonStyle()
          .disabled(!store.canUpdateListDraft)
          .accessibilityIdentifier("mobileEditList.confirm")
        }
      }
    }
    // List editor detents: medium + large for quick naming or full descriptions.
    .mobileCompactEditorSheetPresentation()
  }

  private func submit() {
    Task {
      let updated = await store.updateList(list)
      if updated {
        isPresented = false
      }
    }
  }
}
