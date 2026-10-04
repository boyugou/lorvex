import LorvexCore
import SwiftUI

/// Modal editor for an existing memory entry. Owns its OWN draft (seeded from the
/// entry) rather than the store's shared new-entry draft, so opening it never
/// clobbers text the user left half-typed in the New Memory sheet.
@MainActor
struct MobileStoreMemoryEditorSheet: View {
  @Bindable var store: MobileStore
  let entry: MemoryEntry
  @Environment(\.dismiss) private var dismiss
  @State private var key: String
  @State private var content: String
  @FocusState private var focusedField: Field?

  private enum Field {
    case key
    case content
  }

  init(store: MobileStore, entry: MemoryEntry) {
    self.store = store
    self.entry = entry
    _key = State(initialValue: entry.key)
    _content = State(initialValue: entry.content)
  }

  private var canSave: Bool {
    !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !store.isSavingMemory
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
            text: $key
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
            text: $content,
            axis: .vertical
          )
          .lineLimit(4...12)
          .focused($focusedField, equals: .content)
          .submitLabel(.done)
          .onSubmit { save() }
          .accessibilityIdentifier("mobileMemory.editor.content")
        }
      }
      .mobileSheetTitle(
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
            dismiss()
          }
          .accessibilityIdentifier("mobileMemory.editor.cancel")
        }

        ToolbarItem(placement: .confirmationAction) {
          Button {
            save()
          } label: {
            if store.isSavingMemory {
              ProgressView().tint(.white)
            } else {
              Text(
                String(
                  localized: "common.save", defaultValue: "Save", table: "Localizable",
                  bundle: MobileL10n.bundle))
            }
          }
          .mobileProminentToolbarButtonStyle()
          .disabled(!canSave)
          .accessibilityIdentifier("mobileMemory.editor.save")
        }
      }
    }
    .mobileCompactEditorSheetPresentation()
  }

  private func save() {
    Task {
      if await store.saveMemoryEntryEdit(originalKey: entry.key, newKey: key, content: content) {
        dismiss()
      }
    }
  }
}
