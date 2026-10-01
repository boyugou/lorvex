import SwiftUI

/// Shared design tokens for every Lorvex Apple surface (macOS, iOS, iPadOS,
/// watchOS).
///
/// Typography, spacing, and radius tokens; the color and surface tokens live in
/// `LorvexDesignSystem.swift` (`LorvexDesign.Palette`). The contract every
/// surface composes from is documented in `docs/design/DESIGN_SYSTEM.md`.
public enum LorvexDesign {
  /// Semantic typography scale, tuned per platform.
  ///
  /// Both platforms use the system's native reading sizes: on iOS/iPadOS
  /// row titles are `.body` (17pt) and metadata `.subheadline` /
  /// `.footnote`, the sizes Apple's own list-based apps use, so rows read at the
  /// density of the platform rather than one notch larger. On macOS the primary
  /// row tokens hold a fixed 14pt: a system font can carry a custom point size
  /// or track Dynamic Type, not both, and 14pt is the deliberate reading size
  /// for content rows on a pointer-driven surface (see `primaryText`). Every
  /// other token is built on a Dynamic Type text style and scales with the
  /// user's accessibility settings.
  public enum Typography {
    #if os(macOS)
    /// Screen / pane title (e.g. the task title field).
    public static let screenTitle = Font.system(.title, design: .default).weight(.semibold)
    /// The name a detail pane leads with (a habit's or memory's title).
    public static let detailTitle = Font.system(.title2, design: .default).weight(.semibold)
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
    /// Screen title where a view draws its own (system navigation titles are
    /// preferred).
    public static let screenTitle = Font.system(.largeTitle, design: .default).weight(.bold)
    /// The name a detail screen leads with (a task's, habit's, or memory's
    /// title): one step above a row title so the screen reads as being about
    /// that item, below a screen title so it does not compete with navigation.
    public static let detailTitle = Font.system(.title2, design: .default).weight(.semibold)
    /// Card or section title.
    public static let sectionHeader = Font.system(.headline, design: .default)
    /// Primary row text — the main content of a row (task names, notes, editors).
    public static let primaryText = Font.system(.body, design: .default)
    /// Emphasized primary text where a row needs a touch more weight.
    public static let primaryEmphasis = Font.system(.body, design: .default).weight(.semibold)
    /// Secondary / metadata text — labels, captions, status lines.
    public static let secondaryText = Font.system(.subheadline, design: .default)
    /// Tertiary text — dense, low-emphasis metadata in compact content rows
    /// (timestamps, counts, chips).
    public static let tertiaryText = Font.system(.footnote, design: .default)
    #endif
  }

  /// Spacing scale for consistent, generous padding and inter-element gaps.
  public enum Spacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 6
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

  /// Widths of columns that hold text, at the default text size. A view scales
  /// them with the text through `@ScaledMetric`, relative to the style the
  /// column holds on iPhone and iPad, so the text keeps fitting as it grows.
  public enum TextColumn {
    /// Holds the widest clock time ("10:40 AM") in `Typography.secondaryText`
    /// with monospaced digits, with points to spare at every size down to the
    /// smallest: 60 for the callout style on macOS, 72 for the subheadline
    /// style on iOS and iPadOS. The timeline rows, the now marker, and the
    /// assistant's change rows set their times in this column.
    #if os(macOS)
    public static let clockTime: CGFloat = 60
    #else
    public static let clockTime: CGFloat = 72
    #endif

    /// Holds the widest review day ("Wed, May 20", "10月30日 周五") in
    /// `Typography.secondaryText` semibold at every size from the smallest up
    /// to xLarge: 84 for the callout style on macOS, 104 for the subheadline
    /// style on iOS and iPadOS. The week review's day rows set their day in
    /// this column, so every day's note starts at one edge.
    #if os(macOS)
    public static let reviewDay: CGFloat = 84
    #else
    public static let reviewDay: CGFloat = 104
    #endif
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

    /// Height below which a timed block drops its vertical padding and clips
    /// its text, so the one title line it can hold stays inside it. A block
    /// only gets this short when another block starts right after it: otherwise
    /// `CalendarGridModel.minBlockMinutes` holds it open to 20 minutes, which
    /// is at least 16pt on every grid.
    public static let tightBlockHeight: CGFloat = 16

    /// Lane width below which a timed block on the phone grid goes compact:
    /// its title alone, in ``compactBlockText``, wrapping as far as the block
    /// is tall, with no time line and no completion ring. A seven-day week on
    /// a phone gives each day about 44pt, where a title beside a ring or over
    /// a time keeps only a letter or two.
    public static let compactLaneWidth: CGFloat = 64

    /// The title face of a compact block (``compactLaneWidth``) and of the
    /// all-day pills in columns that narrow: SF's condensed width, so a
    /// typical word ("Refactor", "Customer") fits a phone week's column whole
    /// instead of breaking inside the word.
    public static let compactBlockText = Font.system(.caption2, design: .default)
      .weight(.medium).width(.condensed)

    /// Gap between the rightmost event lane and the trailing edge of its day
    /// column. Without it a block ends two points from the edge, which on a
    /// wide single-day column (iPad regular width) reads as an event running
    /// off the screen rather than sitting inside the day. Lane placement
    /// divides the column width minus this inset; the column's own width is
    /// unchanged, so the drag-across-days step still measures a whole day.
    public static let laneTrailingInset: CGFloat = 8

    /// The trailing gap for a day column `columnWidth` wide: the full
    /// ``laneTrailingInset`` on a wide column, shrinking with the column to 2pt
    /// on a phone week's, where 8pt would take a fifth of the block's width
    /// from its title and the column's own gridline already parts it from the
    /// next day.
    public static func laneTrailingInset(columnWidth: CGFloat) -> CGFloat {
      min(laneTrailingInset, max(2, columnWidth * 0.04))
    }
  }
}
