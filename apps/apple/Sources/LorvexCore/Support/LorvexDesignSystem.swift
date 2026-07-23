import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

// The visual layer that sits on top of the bare type/spacing/radius tokens in
// `LorvexDesign`: a considered accent, a semantic status palette, surface +
// elevation tokens, and card-scale radii. This is what moves the app from "bare
// system components" to a cohesive, refined-native design language. Colors are
// always semantic (they adapt to light/dark); views never hardcode hex.

extension LorvexDesign {
  /// The Lorvex color system. Most surfaces use the system semantic colors so the
  /// app stays native and theme-correct; the accent and the status hues are the
  /// deliberate brand layer. Tuned for both light and dark.
  public enum Palette {
    /// The Lorvex accent — a confident, slightly deep blue that reads calm and
    /// focused (the right tone for a planner) while staying close to the platform.
    /// Centralized here so the whole app's tint is one tunable decision.
    public static let accent = dynamic(
      light: Color(red: 0.13, green: 0.40, blue: 0.92),
      dark: Color(red: 0.40, green: 0.58, blue: 1.0))

    // MARK: Status hues — the small, meaningful palette that encodes task state.

    /// Overdue / past-due — demands attention.
    public static let overdue = Color.red
    /// Due today / due soon — gentle urgency.
    public static let dueSoon = Color.orange
    /// In the current focus plan.
    public static let focus = accent
    /// Someday / parked — deliberately low-energy.
    public static let someday = Color.indigo
    /// Completed / success.
    public static let done = Color.green

    // MARK: Surfaces — grouped background + an explicit elevated card surface.

    /// The base grouped background a screen sits on.
    public static let groupedBackground: Color = {
      #if canImport(UIKit) && !os(watchOS)
        return Color(uiColor: .systemGroupedBackground)
      #else
        return Color.clear
      #endif
    }()

    /// The elevated surface cards sit on, one step above `groupedBackground`.
    public static let card: Color = {
      #if canImport(UIKit) && !os(watchOS)
        return Color(uiColor: .secondarySystemGroupedBackground)
      #elseif canImport(AppKit)
        return Color(nsColor: .controlBackgroundColor)
      #else
        return Color.gray.opacity(0.12)
      #endif
    }()

    /// Hairline separators inside cards.
    public static let separator: Color = {
      #if canImport(UIKit) && !os(watchOS)
        return Color(uiColor: .separator)
      #elseif canImport(AppKit)
        return Color(nsColor: .separatorColor)
      #else
        return Color.secondary.opacity(0.3)
      #endif
    }()

    /// Builds a color that resolves differently in light and dark. Falls back to
    /// the light value on platforms without a dynamic provider.
    static func dynamic(light: Color, dark: Color) -> Color {
      #if canImport(UIKit) && !os(watchOS)
        return Color(uiColor: UIColor { traits in
          traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
      #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
          let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
          return isDark ? NSColor(dark) : NSColor(light)
        })
      #else
        return light
      #endif
    }
  }

  /// Soft elevation for cards. Kept subtle — a refined-native card reads through
  /// surface contrast and a faint shadow, not a heavy drop shadow.
  public enum Elevation {
    public static let cardShadowColor = Color.black.opacity(0.06)
    public static let cardShadowRadius: CGFloat = 8
    public static let cardShadowY: CGFloat = 2
  }
}

extension LorvexDesign.Radius {
  /// Card / grouped-container radius. Continuous corners at this scale are the
  /// modern card look; the existing `s`/`m` (6/10) are too tight for cards.
  public static let card: CGFloat = 18
}

extension LorvexDesign.Spacing {
  /// Standard inset for card content and screen gutters.
  public static let cardPadding: CGFloat = 16
}
