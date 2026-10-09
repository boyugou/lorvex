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
  /// Whether `message` points at the screen's toolbar ＋ button. The tab bar
  /// holds a second ＋ that opens task capture, so a plain ＋ in the message
  /// could mean either button. When set, each ＋ in the message is drawn in
  /// the accent color the toolbar button wears, which marks it as the toolbar's.
  var pointsAtToolbarAdd = false
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
          messageText(message)
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

  private func messageText(_ message: String) -> Text {
    pointsAtToolbarAdd ? Text(Self.accentingAddSymbol(in: message)) : Text(message)
  }
}

extension MobileEmptyState {
  /// The plus sign (U+FF0B) that every shipped translation of a message
  /// pointing at an add button writes.
  private static let addSymbol = "＋"

  /// `message` with each ＋ drawn in the accent color; the rest of the text
  /// carries no attributes, so it keeps the style the caller gives the `Text`.
  static func accentingAddSymbol(in message: String) -> AttributedString {
    var accented = AttributedString()
    for (position, part) in message.components(separatedBy: addSymbol).enumerated() {
      if position > 0 {
        var symbol = AttributedString(addSymbol)
        symbol.foregroundColor = LorvexDesign.Palette.accent
        accented.append(symbol)
      }
      accented.append(AttributedString(part))
    }
    return accented
  }

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
