import SwiftUI

struct MobileStoreCreateListSheet: View {
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
          .accessibilityLabel(
            String(
              localized: "lists.field.name.a11y", defaultValue: "List name", table: "Localizable",
              bundle: MobileL10n.bundle)
          )
          .accessibilityIdentifier("mobileCreateList.name")
          TextField(
            String(
              localized: "lists.field.description", defaultValue: "Description",
              table: "Localizable", bundle: MobileL10n.bundle), text: $store.listDraft.description,
            axis: .vertical
          )
          .lineLimit(3...5)
          .focused($focusedField, equals: .description)
          .submitLabel(.done)
          .onSubmit { submit() }
          .accessibilityLabel(
            String(
              localized: "lists.field.description.a11y", defaultValue: "List description",
              table: "Localizable", bundle: MobileL10n.bundle)
          )
          .accessibilityIdentifier("mobileCreateList.description")
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
              ProgressView()
            } else {
              Text(
                String(
                  localized: "common.create", defaultValue: "Create", table: "Localizable",
                  bundle: MobileL10n.bundle))
            }
          }
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
