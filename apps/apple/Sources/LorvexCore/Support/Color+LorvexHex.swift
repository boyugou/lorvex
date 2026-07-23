import SwiftUI
#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

extension Color {
  /// `#RRGGBB` for this color resolved in the sRGB space, or `nil` when the
  /// platform color can't be resolved to RGB components (e.g. a pattern color,
  /// or a platform without AppKit/UIKit such as watchOS). The inverse of
  /// ``init(lorvexHex:)`` — used for calendar and provider colors persisted
  /// as `#RRGGBB` strings.
  public var lorvexHexString: String? {
    #if canImport(AppKit)
      guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
      let r = srgb.redComponent, g = srgb.greenComponent, b = srgb.blueComponent
    #elseif canImport(UIKit)
      var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
      guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
    #else
      return nil
    #endif
    return String(
      format: "#%02X%02X%02X",
      Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
  }

  /// Parses a `#RRGGBB` / `RRGGBB` / `#RRGGBBAA` hex string into an sRGB
  /// color. Returns `nil` for unparseable or nil input so callers can fall
  /// back to a system color (e.g. `Color(lorvexHex: event.color) ?? .accentColor`).
  ///
  /// Shared by the macOS week grid and the iPhone day column, which render
  /// calendar-event colors from the stored hex string.
  public init?(lorvexHex hexString: String?) {
    guard var hex = hexString?.trimmingCharacters(in: .whitespaces), !hex.isEmpty else {
      return nil
    }
    if hex.hasPrefix("#") { hex.removeFirst() }
    guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else {
      return nil
    }
    let r, g, b, a: Double
    if hex.count == 8 {
      r = Double((value >> 24) & 0xFF) / 255
      g = Double((value >> 16) & 0xFF) / 255
      b = Double((value >> 8) & 0xFF) / 255
      a = Double(value & 0xFF) / 255
    } else {
      r = Double((value >> 16) & 0xFF) / 255
      g = Double((value >> 8) & 0xFF) / 255
      b = Double(value & 0xFF) / 255
      a = 1
    }
    self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
  }
}
