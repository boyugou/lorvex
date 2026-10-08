import LorvexCore
import SwiftUI

/// The add / edit composer for memory entries, pinned above the entry list.
///
/// A key + content draft shared by the create and edit flows. Memory is the
/// assistant's context about the user, so the app writes it as the AI actor,
/// through the same `LorvexMemoryServicing` upsert as every other memory write.
struct MemoryComposerCard: View {
  @Bindable var store: AppStore
  var cancelCreate: (() -> Void)?
  /// Called after a draft is persisted, so the owner can dismiss the composer.
  var onSaved: (() -> Void)? = nil

  var body: some View {
    MemoryCard {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        if let editingKey = store.memoryEditingKey {
          editingBanner(editingKey)
        } else {
          Label(
            String(localized: "memory.composer.title", defaultValue: "New Memory", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "sparkles"
          )
          .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("memory.composer.title")
        }

        fieldLabel(String(localized: "memory.field.key", defaultValue: "Key", table: "Localizable", bundle: LorvexL10n.bundle))
        TextField(
          String(
            localized: "memory.field.key.example", defaultValue: "e.g. coffee order",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          text: $store.memoryKeyDraft
        )
        .textFieldStyle(.plain)
        .font(LorvexDesign.Typography.primaryEmphasis)
        .accessibilityIdentifier("memory.field.key")

        fieldLabel(String(
          localized: "memory.composer.content_label", defaultValue: "Content",
          table: "Localizable",
          bundle: LorvexL10n.bundle))
        LorvexPlainTextEditor(
          text: $store.memoryContentDraft,
          placeholder: String(
            localized: "memory.field.content",
            defaultValue: "What should the assistant remember?",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          minHeight: 60,
          maxHeight: 96,
          fontSize: 13
        )
        .accessibilityIdentifier("memory.field.content")

        HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
          // A visible reason for the disabled Save: both fields are required, and
          // placeholders alone left it unclear which one was still missing.
          if showsSaveRequirementHint {
            Label(
              String(
                localized: "memory.composer.requirement",
                defaultValue: "A key and content are both required to save.",
                table: "Localizable",
                bundle: LorvexL10n.bundle),
              systemImage: "info.circle"
            )
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .accessibilityIdentifier("memory.save.requirement")
          }
          Spacer(minLength: 0)
          if let cancelCreate, store.memoryEditingKey == nil {
            Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: LorvexL10n.bundle)) {
              cancelCreate()
            }
            .buttonStyle(.link)
            .controlSize(.small)
            .accessibilityIdentifier("memory.create.cancel")
          }
          Button {
            Task {
              if await store.saveMemoryDraft() { onSaved?() }
            }
          } label: {
            Label(
              store.memoryEditingKey == nil
                ? String(localized: "common.create", defaultValue: "Create", table: "Localizable", bundle: LorvexL10n.bundle)
                : String(localized: "memory.composer.update", defaultValue: "Update", table: "Localizable", bundle: LorvexL10n.bundle),
              systemImage: "brain")
          }
          .buttonStyle(.borderedProminent)
          .disabled(!store.canSaveMemoryDraft)
          .accessibilityIdentifier("memory.save")
        }
      }
    }
  }

  private func fieldLabel(_ text: String) -> some View {
    Text(text)
      .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
      .foregroundStyle(.secondary)
  }

  /// Names the active edit plainly and offers a one-click exit back to the empty
  /// create state, so editing the shared composer is never a silent hijack.
  private func editingBanner(_ key: String) -> some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "pencil.circle")
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(LorvexDesign.Palette.warning)
        .accessibilityHidden(true)
      Text(
        String(
          format: String(
            localized: "memory.editing_banner",
            defaultValue: "Editing \u{201C}%@\u{201D}",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ),
          MemoryEntry.displayTitle(forKey: key)
        )
      )
      .font(LorvexDesign.Typography.secondaryText)
      .lineLimit(1)

      Spacer(minLength: LorvexDesign.Spacing.m)

      Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: LorvexL10n.bundle)) {
        store.cancelEditingMemory()
      }
      .buttonStyle(.link)
      .controlSize(.small)
      .accessibilityIdentifier("memory.edit.cancel")
    }
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(LorvexDesign.Palette.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    .accessibilityIdentifier("memory.edit.banner")
  }

  /// True once the user has started a draft (one field filled) but it isn't yet
  /// saveable — so the disabled Save button shows a reason rather than appearing
  /// broken.
  private var showsSaveRequirementHint: Bool {
    guard !store.canSaveMemoryDraft else { return false }
    let key = store.memoryKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    let content = store.memoryContentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    return !key.isEmpty || !content.isEmpty
  }
}

/// An elevated surface for the memory composer. Routes through the shared
/// `.lorvexCard()` chrome so the composer matches every other card in the app
/// (`Palette.card` surface, `Radius.card` corners, the card shadow). The entry
/// list renders as native `List` rows rather than cards.
struct MemoryCard<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    content.lorvexCard()
  }
}
