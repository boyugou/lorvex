import LorvexCore
import SwiftUI

/// A colored, rounded-square icon tile — the single highest-leverage atom for a
/// "designed, not bare" look. A tinted fill behind a hierarchical SF Symbol, used
/// as the leading element of catalog rows, Settings/More rows, and section
/// leaders. This is the texture mature task apps have; achieved natively.
///
/// `size` is the tile's side at the default text size. The tile grows with the
/// body text from there up to ``largestScaledSize``, so a row's leading tile
/// keeps in proportion with the row's text at large sizes, and it never
/// shrinks below `size`. A tile designed at ``largestScaledSize`` or larger (a
/// page's header tile, a picker's preview) keeps its size.
struct MobileIconTile: View {
  /// The largest side a tile grows to with the text.
  nonisolated static let largestScaledSize: CGFloat = 48

  /// The side of a tile designed at `designSize` when `scaled` is that size
  /// scaled to the current text size: it grows with the text, never shrinks
  /// below `designSize`, and stops at ``largestScaledSize`` (a tile designed
  /// larger keeps its size).
  nonisolated static func side(designSize: CGFloat, scaled: CGFloat) -> CGFloat {
    min(max(scaled, designSize), max(designSize, largestScaledSize))
  }

  let symbol: String
  let tint: Color
  let size: CGFloat
  @ScaledMetric private var scaledSize: CGFloat

  /// Builds a tile from a raw icon string. Lists/habits can store an SF Symbol
  /// name OR an emoji; for a cohesive, designed look every tile renders a tinted
  /// SF Symbol, so an emoji or any non-symbol value resolves to `fallback` (e.g.
  /// the canonical Inbox's "📥" → a clean tray) rather than mixing emoji into the
  /// tinted tiles or rendering the "?" missing-glyph box.
  init(icon: String?, fallback: String, tint: Color = LorvexDesign.Palette.accent, size: CGFloat = 30) {
    self.init(symbol: LorvexSymbol.name(for: icon, fallback: fallback), tint: tint, size: size)
  }

  init(symbol: String, tint: Color = LorvexDesign.Palette.accent, size: CGFloat = 30) {
    self.symbol = symbol
    self.tint = tint
    self.size = size
    _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: .body)
  }

  /// The tile's side at the current text size.
  private var side: CGFloat {
    Self.side(designSize: size, scaled: scaledSize)
  }

  var body: some View {
    RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
      .fill(tint.opacity(0.16))
      .frame(width: side, height: side)
      .overlay {
        Image(systemName: symbol.isEmpty ? "circle.fill" : symbol)
          .font(.system(size: side * 0.5, weight: .semibold))
          .foregroundStyle(tint)
      }
      .accessibilityHidden(true)
  }
}

/// Lays a label out in the columns of a tiled row: the icon centered in a
/// column as wide as a ``MobileIconTile`` of `tileSize` at the current text
/// size, then the title at the spacing tiled rows use. An action row among
/// tiled rows (the "New List" row that closes a card of lists) therefore
/// starts its title where theirs start, which is also where the card's
/// separators start, and its icon shares their center line. The icon sits on
/// the title's first baseline, so a title that wraps keeps it beside the first
/// line. VoiceOver reads the title alone; the icon is decoration.
struct MobileTileColumnLabelStyle: LabelStyle {
  var tileSize: CGFloat = 30

  func makeBody(configuration: Configuration) -> some View {
    MobileTileColumnLabel(configuration: configuration, tileSize: tileSize)
  }
}

private struct MobileTileColumnLabel: View {
  let configuration: LabelStyleConfiguration
  let tileSize: CGFloat
  @ScaledMetric private var scaledSize: CGFloat

  init(configuration: LabelStyleConfiguration, tileSize: CGFloat) {
    self.configuration = configuration
    self.tileSize = tileSize
    _scaledSize = ScaledMetric(wrappedValue: tileSize, relativeTo: .body)
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.m) {
      configuration.icon
        .frame(width: MobileIconTile.side(designSize: tileSize, scaled: scaledSize))
        .accessibilityHidden(true)
      configuration.title
    }
  }
}
