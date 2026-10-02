import SwiftUI

/// The type scale of the Home Screen and desktop widgets: one font per role,
/// each a text style chosen for the platform.
///
/// WidgetKit gives a Mac desktop widget a canvas about the size of an
/// iPhone's, but macOS text styles run smaller than iOS's (its caption,
/// caption2, and footnote are all 10 points), so the styles that fit an
/// iPhone widget would leave a Mac widget's text small and its levels
/// indistinct. Each role therefore names a style per platform, a step or two
/// apart, so a widget keeps the same proportions on both:
///
/// | Role | iOS | macOS |
/// |---|---|---|
/// | `label` | footnote semibold (13) | callout semibold (12) |
/// | `title` | headline (17) | title3 semibold (15) |
/// | `display` | title3 semibold (20) | title2 semibold (17) |
/// | `row` | subheadline (15) | body (13) |
/// | `meta` | footnote (13) | subheadline (11) |
/// | `foot` | caption (12) | subheadline (11) |
/// | `tile` | caption medium (12) | subheadline medium (11) |
///
/// The sizes are each platform's defaults; on iOS they follow the reader's
/// text size. The Lock Screen families keep the system's accessory styles.
public enum WidgetType {
  /// The widget's name at its top: "Today", the list a Today widget shows,
  /// "Habits", "Progress".
  public static var label: Font {
    #if os(macOS)
      .callout.weight(.semibold)
    #else
      .footnote.weight(.semibold)
    #endif
  }

  /// The lead task's title on the small and medium widgets, and the line
  /// saying what is left of the day.
  public static var title: Font {
    #if os(macOS)
      .title3.weight(.semibold)
    #else
      .headline
    #endif
  }

  /// The large widget's lead title and its line saying what is left of the
  /// day.
  public static var display: Font {
    #if os(macOS)
      .title2.weight(.semibold)
    #else
      .title3.weight(.semibold)
    #endif
  }

  /// A task row's title.
  public static var row: Font { .system(rowTextStyle) }

  /// The text style of ``row``, for a metric that grows with a row's text,
  /// such as the row's height.
  public static var rowTextStyle: Font.TextStyle {
    #if os(macOS)
      .body
    #else
      .subheadline
    #endif
  }

  /// A task's time, state, or estimate, beside its row or under the lead.
  public static var meta: Font {
    #if os(macOS)
      .subheadline
    #else
      .footnote
    #endif
  }

  /// The foot line and the stale capsule: what follows the rows on screen.
  public static var foot: Font {
    #if os(macOS)
      .subheadline
    #else
      .caption
    #endif
  }

  /// A habit tile's name, and the count of tiles left out.
  public static var tile: Font {
    #if os(macOS)
      .subheadline.weight(.medium)
    #else
      .caption.weight(.medium)
    #endif
  }
}
