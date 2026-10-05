import SwiftUI

/// The line under a search result's title that says why the result matched: a
/// glyph for the field the text comes from, then the excerpt with the matched
/// term in bold and the primary color.
///
/// Drawn in the quiet metadata face so it never competes with the title, on
/// one line (up to three at accessibility text sizes, where a single line
/// would show almost nothing). A host row that supplies its own VoiceOver
/// label adds ``LorvexTaskSearchMatch/text`` to it; a row that does not reads
/// the excerpt from this view.
public struct LorvexSearchExcerptLine: View {
  public let match: LorvexTaskSearchMatch
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(match: LorvexTaskSearchMatch) {
    self.match = match
  }

  public var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.xs) {
      Image(systemName: match.field.symbolName)
        .imageScale(.small)
        .accessibilityHidden(true)
      Text(excerpt)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
    }
    .font(LorvexDesign.Typography.tertiaryText)
    .foregroundStyle(.secondary)
  }

  private var excerpt: AttributedString {
    var excerpt = match.attributedExcerpt
    for run in excerpt.runs where run.inlinePresentationIntent == .stronglyEmphasized {
      excerpt[run.range].foregroundColor = .primary
    }
    return excerpt
  }
}

extension LorvexTaskSearchMatch.Field {
  /// The symbol the inspector uses for the same field, so the glyph names where
  /// the text lives.
  fileprivate var symbolName: String {
    switch self {
    case .notes: "note.text"
    case .tags: "tag"
    case .assistantContext: "sparkles"
    }
  }
}
