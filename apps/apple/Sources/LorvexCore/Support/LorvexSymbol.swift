import Foundation

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// Resolves a stored icon string to an SF Symbol a view can draw.
///
/// A list, habit, or event icon is stored as a free string: usually an SF
/// Symbol name, but it may be an emoji, empty, or a name this system does not
/// have (one set over MCP, or added in a later OS). Drawing any of those as a
/// symbol shows a blank or the "?" box, so a view that draws only symbols
/// passes the stored value through ``name(for:fallback:)``.
public enum LorvexSymbol {
  /// `icon` when it names an SF Symbol on this system, otherwise `fallback`.
  public static func name(for icon: String?, fallback: String) -> String {
    guard let icon, !icon.isEmpty, icon.unicodeScalars.allSatisfy(\.isASCII), exists(icon) else {
      return fallback
    }
    return icon
  }

  private static func exists(_ name: String) -> Bool {
    #if canImport(UIKit)
      UIImage(systemName: name) != nil
    #elseif canImport(AppKit)
      NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    #else
      true
    #endif
  }
}
