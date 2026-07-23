import SwiftUI

@MainActor
struct MobileStoreMemoryEditorSheet: View {
  @Bindable var store: MobileStore
  @Binding var isPresented: Bool
  @FocusState private var focusedField: Field?

  private enum Field {
    case key
    case content
  }

  var body: some View {
    NavigationStack {
      Form {
        Section(
          String(
            localized: "memory.section.edit", defaultValue: "Edit Memory",
            table: "Localizable", bundle: MobileL10n.bundle)
        ) {
          TextField(
            String(
              localized: "memory.field.key", defaultValue: "Key", table: "Localizable",
              bundle: MobileL10n.bundle),
            text: $store.memoryKeyDraft
          )
          .autocorrectionDisabled()
          .focused($focusedField, equals: .key)
          .submitLabel(.next)
          .onSubmit { focusedField = .content }
          .accessibilityIdentifier("mobileMemory.editor.key")

          TextField(
            String(
              localized: "memory.field.content", defaultValue: "Content", table: "Localizable",
              bundle: MobileL10n.bundle),
            text: $store.memoryContentDraft,
            axis: .vertical
          )
          .lineLimit(4...12)
          .focused($focusedField, equals: .content)
          .submitLabel(.done)
          .onSubmit { save() }
          .accessibilityIdentifier("mobileMemory.editor.content")
        }
      }
      .navigationTitle(
        String(
          localized: "memory.section.edit", defaultValue: "Edit Memory",
          table: "Localizable", bundle: MobileL10n.bundle)
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(
            String(
              localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
              bundle: MobileL10n.bundle)
          ) {
            store.clearMemoryDraft()
            isPresented = false
          }
          .accessibilityIdentifier("mobileMemory.editor.cancel")
        }

        ToolbarItem(placement: .confirmationAction) {
          Button {
            save()
          } label: {
            if store.isSavingMemory {
              ProgressView()
            } else {
              Text(
                String(
                  localized: "common.save", defaultValue: "Save", table: "Localizable",
                  bundle: MobileL10n.bundle))
            }
          }
          .disabled(!store.canSaveMemoryDraft)
          .accessibilityIdentifier("mobileMemory.editor.save")
        }
      }
    }
    .mobileCompactEditorSheetPresentation()
    .onDisappear {
      if store.memoryEditingKey != nil {
        store.clearMemoryDraft()
      }
    }
  }

  private func save() {
    Task {
      if await store.saveMemoryDraft() {
        isPresented = false
      }
    }
  }
}
