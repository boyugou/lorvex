import LorvexCore
import SwiftUI

/// A memory entry's detail: its title, the note's text, when it was last
/// updated, and the edit and delete actions. The panel fills the width it is
/// given: a split's detail pane as it is, and a pushed screen inset to the
/// enclosing screen's readable margin, which a scroll view only honors when it
/// applies the margin itself.
struct MobileMemoryDetailPanel: View {
  let entry: MemoryEntry
  let isSaving: Bool
  let edit: () -> Void
  let delete: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
      .padding(LorvexDesign.Spacing.xl)
    }
    .mobileReadableScrollMargins()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.background)
    .accessibilityIdentifier("mobileMemory.detailPanel")
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      Image(systemName: "sparkles")
        .font(LorvexDesign.Typography.screenTitle)
        .foregroundStyle(.tint)
        .frame(width: 56, height: 56)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m, style: .continuous))
        .accessibilityHidden(true)

      Text(userContent: entry.displayTitle)
        .font(LorvexDesign.Typography.detailTitle)
        .textSelection(.enabled)
    }
  }

  private var content: some View {
    Text(userContent: entry.content)
      .font(LorvexDesign.Typography.primaryText)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(LorvexDesign.Spacing.l)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.card, style: .continuous))
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
        delete()
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
    }
  }
}
