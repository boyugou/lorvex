import LorvexCore
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// A colored, rounded-square icon tile — the single highest-leverage atom for a
/// "designed, not bare" look. A tinted fill behind a hierarchical SF Symbol, used
/// as the leading element of catalog rows, Settings/More rows, and section
/// leaders. This is the texture mature task apps have; achieved natively.
struct MobileIconTile: View {
  let symbol: String
  var tint: Color = LorvexDesign.Palette.accent
  var size: CGFloat = 30

  /// Builds a tile from a raw icon string. Lists/habits can store an SF Symbol
  /// name OR an emoji; for a cohesive, designed look every tile renders a tinted
  /// SF Symbol, so an emoji or any non-symbol value resolves to `fallback` (e.g.
  /// the canonical Inbox's "📥" → a clean tray) rather than mixing emoji into the
  /// tinted tiles or rendering the "?" missing-glyph box.
  init(icon: String?, fallback: String, tint: Color = LorvexDesign.Palette.accent, size: CGFloat = 30) {
    if let icon, !icon.isEmpty, icon.unicodeScalars.allSatisfy(\.isASCII), Self.isValidSymbol(icon) {
      self.init(symbol: icon, tint: tint, size: size)
    } else {
      self.init(symbol: fallback, tint: tint, size: size)
    }
  }

  /// Whether `name` is a real SF Symbol (so we never render the "?" box).
  static func isValidSymbol(_ name: String) -> Bool {
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
  }

  var body: some View {
    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
      .fill(tint.opacity(0.16))
      .frame(width: size, height: size)
      .overlay {
        Image(systemName: symbol.isEmpty ? "circle.fill" : symbol)
          .font(.system(size: size * 0.5, weight: .semibold))
          .foregroundStyle(tint)
      }
      .accessibilityHidden(true)
  }
}
