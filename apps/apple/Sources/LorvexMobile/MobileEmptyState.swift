import LorvexCore
import SwiftUI

/// A reusable, refined empty-state — the replacement for ad-hoc
/// `ContentUnavailableView` usage across the mobile surface.
///
/// `ContentUnavailableView` is a self-centering container that expands to fill
/// both axes. Placed inside a `List` `Section` row it gets an unbounded height
/// proposal, inflates the row, and stretches any prominent action button into a
/// tall bar (the Today "No Open Tasks" blue-bar bug). This component is bounded:
/// a normal-height row safe inside a section.
struct MobileEmptyState: View {
  let icon: String
  var tint: Color = LorvexDesign.Palette.accent
  let title: String
  var message: String? = nil
  var actionTitle: String? = nil
  var action: (() -> Void)? = nil

  var body: some View {
    inlineBody
  }

  private var inlineBody: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      MobileIconTile(symbol: icon, tint: tint, size: 40)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(LorvexDesign.Typography.primaryEmphasis)
          .fixedSize(horizontal: false, vertical: true)
        if let message {
          Text(message)
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: LorvexDesign.Spacing.s)
      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .buttonStyle(.bordered)
          .controlSize(.small)
          .fixedSize()
      }
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
  }
}

extension MobileEmptyState {
  /// The no-results row for a `.searchable` list whose query matched nothing.
  /// Bounded like every other `MobileEmptyState`, so it sits in a `List`
  /// `Section` at normal row height where `ContentUnavailableView.search` would
  /// inflate the row. The title quotes the trimmed query.
  static func search(text query: String) -> MobileEmptyState {
    MobileEmptyState(
      icon: "magnifyingglass",
      tint: LorvexDesign.Palette.neutral,
      title: String(
        format: String(
          localized: "search.empty.title", defaultValue: "No Results for “%@”",
          table: "Localizable", bundle: MobileL10n.bundle),
        query.trimmingCharacters(in: .whitespacesAndNewlines)),
      message: String(
        localized: "search.empty.message",
        defaultValue: "Check the spelling or try a different search.",
        table: "Localizable", bundle: MobileL10n.bundle))
  }
}
