import LorvexCore
import SwiftUI

/// A memory entry's detail: its title, the note's text, when it was last
/// updated, and the edit and delete actions. Delete asks first, with a
/// confirmation that points at its button. The panel fills the width it is
/// given: a split's detail pane as it is, and a pushed screen inset to the
/// enclosing screen's readable margin, which a scroll view only honors when it
/// applies the margin itself.
struct MobileMemoryDetailPanel: View {
  let entry: MemoryEntry
  let isSaving: Bool
  let edit: () -> Void
  /// Deletes the entry once the confirmation is accepted.
  let delete: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var isConfirmingDelete = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xl) {
        header
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
          content
          updatedCaption
            .padding(.horizontal, LorvexDesign.Spacing.l)
        }
        actions
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .mobileDetailPanelPadding()
    }
    .mobileReadableScrollMargins()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LorvexDesign.Palette.groupedBackground)
    .accessibilityIdentifier("mobileMemory.detailPanel")
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      MobileIconTile(symbol: "sparkles", size: 56)

      Text(userContent: entry.displayTitle)
        .font(LorvexDesign.Typography.detailTitle)
        .textSelection(.enabled)
        .accessibilityAddTraits(.isHeader)
    }
  }

  private var content: some View {
    Text(userContent: entry.content)
      .font(LorvexDesign.Typography.primaryText)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(LorvexDesign.Spacing.l)
      .background(LorvexDesign.Palette.card, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.card, style: .continuous))
  }

  /// When the note last changed, as a caption under its text: secondary
  /// information, so it takes no card of its own.
  private var updatedCaption: some View {
    Text(
      String(
        format: String(
          localized: "memory.detail.updated_at", defaultValue: "Updated %@", table: "Localizable",
          bundle: MobileL10n.bundle),
        formattedUpdatedAt)
    )
    .font(LorvexDesign.Typography.tertiaryText)
    .foregroundStyle(.secondary)
    .monospacedDigit()
  }

  /// `updatedAt` is the canonical `SyncTimestamp` — always millisecond form
  /// (`…SS.mmmZ`), so it must be parsed with the fractional-seconds formatter
  /// (`iso8601` without `.withFractionalSeconds` returns nil and would silently
  /// fall back to the raw string). Rendered as a readable local date/time.
  private var formattedUpdatedAt: String {
    LorvexDateFormatters.iso8601Fractional.date(from: entry.updatedAt)
      .map { LorvexDateFormatters.dayAndClockTime($0) } ?? entry.updatedAt
  }

  /// Edit and Delete side by side, stacked at accessibility text sizes so
  /// neither label breaks mid-word.
  private var actions: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: LorvexDesign.Spacing.m))
      : AnyLayout(HStackLayout(spacing: LorvexDesign.Spacing.m))
    return layout {
      Button {
        edit()
      } label: {
        Label(
          String(
            localized: "common.edit", defaultValue: "Edit", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "pencil")
      }
      .buttonStyle(.borderedProminent)
      .disabled(isSaving)
      .accessibilityIdentifier("mobileMemory.detail.edit")

      Button(role: .destructive) {
        isConfirmingDelete = true
      } label: {
        Label(
          String(
            localized: "common.delete", defaultValue: "Delete", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "trash")
      }
      .buttonStyle(.bordered)
      .mobileDestructiveBorderedStyle()
      .disabled(isSaving)
      .accessibilityIdentifier("mobileMemory.detail.delete")
      .mobileDeleteConfirmation(
        isPresented: $isConfirmingDelete,
        title: MobileMemoryDeleteCopy.title(for: entry),
        message: MobileMemoryDeleteCopy.message,
        delete: delete
      )
    }
  }
}
