import SwiftUI

/// Shared design tokens for every Lorvex Apple surface (macOS, iOS, iPadOS,
/// visionOS).
///
/// Semantic typography and spacing scales tuned for a calmer, more legible
/// layout than the SwiftUI defaults: larger base text, generous whitespace.
/// Type tokens are built on Dynamic Type text styles so they scale with the
/// user's accessibility settings; colors stay system-driven (`.primary`,
/// `.secondary`) so light and dark both render correctly.
public enum LorvexDesign {
  /// Semantic typography scale, tuned per platform.
  ///
  /// On iOS/iPadOS/visionOS the scale runs one notch larger than the SwiftUI
  /// default a control would otherwise pick (`primaryText` is `.title3` where a
  /// bare `Text` renders `.body`), which reads calmer and more legible on a
  /// touch device. macOS is a denser, pointer-driven surface where that same
  /// "one notch up" reads as oversized and heavy, so the Mac scale steps back to
  /// the platform's native sizes (`.title3` section headers, ~`.body` row text).
  /// The title, section-header, secondary, and tertiary tokens are built on
  /// Dynamic Type text styles and scale with the user's accessibility settings.
  /// The macOS primary row tokens hold a fixed 14pt: a system font can carry a
  /// custom point size or track Dynamic Type, not both, and the size is the
  /// deliberate choice there (see `primaryText`).
  public enum Typography {
    #if os(macOS)
    /// Screen / pane title (e.g. the task title field).
    public static let screenTitle = Font.system(.title, design: .default).weight(.semibold)
    /// Section / disclosure-group header.
    public static let sectionHeader = Font.system(.title3, design: .default).weight(.semibold)
    /// Primary row text — the main content of a row (task names, notes labels).
    /// Fixed 14pt rather than `.body` (13pt): content rows are the surface the
    /// user reads all day, and at 13pt they sit undersized against the window's
    /// whitespace (peer task managers set list titles at ~14). This token does
    /// not track Dynamic Type — a system font keeps either a custom point size
    /// or text-style scaling, not both, and the 14pt size wins here. The
    /// scaling metadata styles below cover the smaller content text.
    public static let primaryText = Font.system(size: 14)
    /// Emphasized primary text where a row needs a touch more weight. Fixed-size
    /// for the same reason as `primaryText`.
    public static let primaryEmphasis = Font.system(size: 14, weight: .medium)
    /// Secondary / metadata text — labels, captions, status lines. Built on the
    /// `.callout` text style (macOS's native 12pt) so it tracks Dynamic Type.
    public static let secondaryText = Font.system(.callout, design: .default)
    /// Tertiary text — dense, low-emphasis metadata in compact content rows
    /// (due dates, durations, tags). Built on the `.subheadline` text style
    /// (macOS's native 11pt) so it tracks Dynamic Type; `.caption` (10pt) is
    /// below comfortable reading size for metadata that still carries meaning.
    public static let tertiaryText = Font.system(.subheadline, design: .default)
    #else
    /// Screen / pane title (e.g. the task title field).
    public static let screenTitle = Font.system(.largeTitle, design: .default).weight(.semibold)
    /// Section / disclosure-group header.
    public static let sectionHeader = Font.system(.title2, design: .default).weight(.semibold)
    /// Primary row text — the main content of a row (task names, notes labels).
    public static let primaryText = Font.system(.title3, design: .default)
    /// Emphasized primary text where a row needs a touch more weight.
    public static let primaryEmphasis = Font.system(.title3, design: .default).weight(.medium)
    /// Secondary / metadata text — labels, captions, status lines.
    public static let secondaryText = Font.system(.body, design: .default)
    /// Tertiary text — dense, low-emphasis metadata in compact content rows
    /// (timestamps, counts, sublabels) where `secondaryText` (`.body`) would
    /// crowd the row.
    public static let tertiaryText = Font.system(.caption, design: .default)
    #endif
  }

  /// Spacing scale for consistent, generous padding and inter-element gaps.
  public enum Spacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 14
    public static let l: CGFloat = 22
    public static let xl: CGFloat = 32
  }

  /// Corner radius scale for grouped containers.
  public enum Radius {
    public static let s: CGFloat = 6
    public static let m: CGFloat = 10
  }

  /// Layout metrics for the calendar timeline grid, kept in the design system so
  /// the grid's vertical scale is a named token like the spacing and radius
  /// scales rather than a bare literal in the grid views.
  public enum CalendarMetrics {
    /// Height of one hour row in the week / day timeline grid. Every timeline
    /// geometry calculation — event-block placement, the now-line offset, and
    /// the drag-to-create / resize math — reads from this one value, so the
    /// whole grid scales together. 48pt yields a 24pt half-hour slot: a
    /// comfortable pointer drag target without making a full day scroll too far.
    public static let hourHeight: CGFloat = 48
  }
}
