import LorvexCore
import SwiftUI

struct MobileStoreEditListSheet: View {
  let list: LorvexList
  @Bindable var store: MobileStore
  @Binding var isPresented: Bool
  @FocusState private var focusedField: Field?

  private enum Field {
    case name
    case description
  }

  var body: some View {
    NavigationStack {
      Form {
        Section(
          String(
            localized: "lists.section.list", defaultValue: "List", table: "Localizable",
            bundle: MobileL10n.bundle)
        ) {
          TextField(
            String(
              localized: "lists.field.name", defaultValue: "Name", table: "Localizable",
              bundle: MobileL10n.bundle), text: $store.listDraft.name
          )
          .focused($focusedField, equals: .name)
          .submitLabel(.next)
          .onSubmit { focusedField = .description }
          .accessibilityIdentifier("mobileEditList.name")
          TextField(
            String(
              localized: "lists.field.description", defaultValue: "Description",
              table: "Localizable", bundle: MobileL10n.bundle), text: $store.listDraft.description,
            axis: .vertical
          )
          .lineLimit(3...6)
          .focused($focusedField, equals: .description)
          .submitLabel(.done)
          .onSubmit { submit() }
          .accessibilityIdentifier("mobileEditList.description")
        }
        Section {
          MobileIconColorPicker(
            icon: $store.listDraft.icon,
            color: $store.listDraft.color,
            fallbackIcon: "tray.fill",
            iconChoices: MobileIconChoices.list
          )
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
        }
      }
      .navigationTitle(
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
              ProgressView()
            } else {
              Text(
                String(
                  localized: "common.save", defaultValue: "Save", table: "Localizable",
                  bundle: MobileL10n.bundle))
            }
          }
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
