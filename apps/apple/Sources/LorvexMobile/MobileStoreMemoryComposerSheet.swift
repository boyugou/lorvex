import LorvexCore
import SwiftUI

/// Sheet for drafting a new memory entry, raised by the Memory workspace's
/// toolbar ＋. It edits the store's shared draft (`memoryKeyDraft` /
/// `memoryContentDraft`), which inbound sync reloads leave untouched, and saves
/// through `MobileStore.saveMemoryDraft`, which clears the draft on success.
/// Cancel discards the draft. While the draft has text the sheet cannot be
/// swiped away, so a half-typed entry is never lost to an accidental drag.
@MainActor
struct MobileStoreMemoryComposerSheet: View {
  @Bindable var store: MobileStore
  @Environment(\.dismiss) private var dismiss
  @FocusState private var focusedField: Field?

  private enum Field {
    case key
    case content
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
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
          .accessibilityIdentifier("mobileMemory.key")

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
          .accessibilityIdentifier("mobileMemory.content")
        } footer: {
          Text(
            String(
              localized: "memory.composer.footer",
              defaultValue:
                "A short key names the memory; the content is what your assistant recalls.",
              table: "Localizable", bundle: MobileL10n.bundle))
        }
      }
      .navigationTitle(
        String(
          localized: "memory.new", defaultValue: "New Memory", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(
            String(
              localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
              bundle: MobileL10n.bundle)
          ) {
            store.clearMemoryDraft()
            dismiss()
          }
          .accessibilityIdentifier("mobileMemory.composer.cancel")
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
          .disabled(!store.canSaveMemoryDraft)
          .accessibilityIdentifier("mobileMemory.save")
        }
      }
      .onAppear { focusedField = .key }
    }
    .interactiveDismissDisabled(hasDraftText)
    .mobileCompactEditorSheetPresentation()
  }

  private var hasDraftText: Bool {
    !store.memoryKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !store.memoryContentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func save() {
    Task {
      if await store.saveMemoryDraft() {
        dismiss()
      }
    }
  }
}
