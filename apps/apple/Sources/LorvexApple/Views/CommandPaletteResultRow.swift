import LorvexCore
import SwiftUI

struct CommandPaletteResultRow: View {
  let result: CommandPaletteResult
  let query: String
  let isHighlighted: Bool
  let activate: () -> Void
  let hover: () -> Void

  private var subtitle: String? {
    if case .openTask(_, _, let subtitle) = result { return subtitle }
    return nil
  }

  var body: some View {
    Button(action: activate) {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Image(systemName: result.systemImage)
          .frame(width: 20)
          .foregroundStyle(isHighlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        VStack(alignment: .leading, spacing: 1) {
          highlightedTitle(result.localizedTitle)
            .font(LorvexDesign.Typography.secondaryText)
            .lineLimit(1)
          if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.secondary)
              .lineLimit(1)
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
          .fill(isHighlighted ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear))
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
