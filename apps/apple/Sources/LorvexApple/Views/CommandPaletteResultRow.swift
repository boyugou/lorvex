import LorvexCore
import SwiftUI

struct CommandPaletteResultRow: View {
  let result: CommandPaletteResult
  let query: String
  let isHighlighted: Bool
  let activate: () -> Void
  let hover: () -> Void

  private var subtitle: String? {
    if case .openTask(_, _, let subtitle, _) = result { return subtitle }
    return nil
  }

  var body: some View {
    Button(action: activate) {
      HStack(spacing: LorvexDesign.Spacing.s) {
        icon
        VStack(alignment: .leading, spacing: 1) {
          highlightedTitle(result.localizedTitle)
            .font(LorvexDesign.Typography.secondaryText)
            .lineLimit(1)
          if let subtitle, !subtitle.isEmpty {
            subtitleLine(subtitle)
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 0)
        if isHighlighted {
          Text("\u{21A9}")
            .font(LorvexDesign.Typography.secondaryText.weight(.medium))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
      }
      .padding(.horizontal, LorvexDesign.Spacing.m)
      .padding(.vertical, LorvexDesign.Spacing.s)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
          .fill(isHighlighted ? AnyShapeStyle(LorvexDesign.Palette.selectionFill) : AnyShapeStyle(.clear))
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .onHover { hovering in
      if hovering { hover() }
    }
    .accessibilityIdentifier("commandPalette.result.\(result.id)")
  }

  /// The dimmed line under a task row: the list's name, then the facts after
  /// it (" · Due today"). A long list name is what truncates; the facts keep
  /// their full width, since they are what tells two similar tasks apart.
  @ViewBuilder
  private func subtitleLine(_ subtitle: String) -> some View {
    if let separator = subtitle.range(of: " · ") {
      HStack(spacing: 0) {
        Text(verbatim: String(subtitle[..<separator.lowerBound])).lineLimit(1)
        Text(verbatim: String(subtitle[separator.lowerBound...])).lineLimit(1).fixedSize()
      }
    } else {
      Text(subtitle).lineLimit(1)
    }
  }

  /// A list wears its own icon and color, as in the sidebar; every other row
  /// shows its symbol, tinted while highlighted.
  @ViewBuilder
  private var icon: some View {
    if case .openList(_, _, let listIcon, let colorHex) = result {
      LorvexListIconView(
        icon: listIcon,
        tint: Color(lorvexHex: colorHex) ?? .accentColor,
        size: 20,
        font: LorvexDesign.Typography.secondaryText)
    } else {
      Image(systemName: result.systemImage)
        .frame(width: 20)
        .foregroundStyle(isHighlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }
  }

  /// Builds a single `AttributedString`-backed `Text` with the query-match
  /// ranges styled semibold/primary, matching the row's base
  /// `.font(LorvexDesign.Typography.secondaryText)` weight-for-weight. A single
  /// `Text` (rather than `Text + Text` concatenation) keeps the result one
  /// reorderable unit for localization and VoiceOver.
  private func highlightedTitle(_ title: String) -> Text {
    let ranges = CommandPaletteResults.matchRanges(of: query, in: title)
    guard !ranges.isEmpty else { return Text(title) }
    var attributed = AttributedString()
    var cursor = title.startIndex
    for range in ranges {
      if cursor < range.lowerBound {
        attributed += AttributedString(title[cursor..<range.lowerBound])
      }
      var highlighted = AttributedString(title[range])
      highlighted.font = LorvexDesign.Typography.secondaryText.weight(.semibold)
      highlighted.foregroundColor = .primary
      attributed += highlighted
      cursor = range.upperBound
    }
    if cursor < title.endIndex {
      attributed += AttributedString(title[cursor...])
    }
    return Text(attributed)
  }
}
