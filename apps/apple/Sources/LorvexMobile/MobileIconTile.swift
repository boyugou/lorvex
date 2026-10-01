import LorvexCore
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

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
  static let largestScaledSize: CGFloat = 48

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
    self.init(symbol: Self.symbol(for: icon, fallback: fallback), tint: tint, size: size)
  }

  /// The SF Symbol a stored icon string renders as: the string itself when it
  /// names a real SF Symbol, otherwise `fallback` (an emoji, an empty string, or
  /// an unknown name).
  nonisolated static func symbol(for icon: String?, fallback: String) -> String {
    if let icon, !icon.isEmpty, icon.unicodeScalars.allSatisfy(\.isASCII), isValidSymbol(icon) {
      return icon
    }
    return fallback
  }

  /// Whether `name` is a real SF Symbol (so we never render the "?" box).
  nonisolated static func isValidSymbol(_ name: String) -> Bool {
    #if canImport(UIKit)
      return UIImage(systemName: name) != nil
    #else
      return true
    #endif
  }

  init(symbol: String, tint: Color = LorvexDesign.Palette.accent, size: CGFloat = 30) {
    self.symbol = symbol
    self.tint = tint
    self.size = size
    _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: .body)
  }

  /// The tile's side at the current text size.
  private var side: CGFloat {
    min(max(scaledSize, size), max(size, Self.largestScaledSize))
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
