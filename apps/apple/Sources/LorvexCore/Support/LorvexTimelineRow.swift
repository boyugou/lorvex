import SwiftUI

/// Sizes the timeline rows and the now marker share, so their columns line up.
public enum LorvexTimelineMetrics {
  /// The width of the marker column where the rows set their time above the
  /// title, given at the default text size. Scaled with the body style, it
  /// stays as wide as a task's circle glyph (about 1.2 times the body size),
  /// so a hold's thin bar, a task's circle, and the now marker's dot share one
  /// center line and the text after them starts at one edge.
  public static let stackedMarkerWidth: CGFloat = 20
  public static let horizontalPadding: CGFloat = 10
}

/// One row of the day drawn as a list: a time, a leading marker, a title, and
/// a quiet duration. The current task's row (Today's Now row) is tinted so the
/// two read as one thing. A row the clock has cleared steps back without
/// losing legibility: its marker fades and its title takes the secondary
/// style, while its time and duration keep theirs. The time column widens with
/// the text; from the size where a column would leave the title a few words a
/// line (``SwiftUI/DynamicTypeSize/stacksTimeColumn``), the marker leads and
/// the time and duration sit above the title, which wraps as far as it needs.
/// Callers own the marker (a task's completion circle, a hold's thin bar in
/// its calendar's color) and any gesture on the row.
public struct LorvexTimelineRow<Marker: View>: View {
  public var time: String
  public var title: String
  public var duration: String?
  public var isCurrent: Bool
  /// A calendar hold or a blocked task: legible, one step quieter than work
  /// the user can pick up.
  public var isQuiet: Bool
  /// A meeting the clock has cleared or a task finished earlier in the day.
  /// Its marker fades to ``LorvexDesign/Palette/pastMarkOpacity`` and its
  /// title is quiet; the row is never dimmed as a whole, since its time and
  /// duration would fall under 2:1.
  public var isPast: Bool
  @ViewBuilder public var marker: () -> Marker
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  /// ``LorvexDesign/TextColumn/clockTime`` scaled with the text, as in the now
  /// marker, so every time in the timeline sits in one column.
  @ScaledMetric(relativeTo: .subheadline) private var timeWidth = LorvexDesign.TextColumn.clockTime
  @ScaledMetric(relativeTo: .body) private var stackedMarkerWidth = LorvexTimelineMetrics.stackedMarkerWidth

  public init(
    time: String, title: String, duration: String?, isCurrent: Bool, isQuiet: Bool,
    isPast: Bool = false,
    @ViewBuilder marker: @escaping () -> Marker
  ) {
    self.time = time
    self.title = title
    self.duration = duration
    self.isCurrent = isCurrent
    self.isQuiet = isQuiet
    self.isPast = isPast
    self.marker = marker
  }

  public var body: some View {
    Group {
      if dynamicTypeSize.stacksTimeColumn {
        stacked
      } else {
        inline
      }
    }
    .padding(.horizontal, LorvexTimelineMetrics.horizontalPadding)
    .frame(minHeight: 36)
    .background {
      if isCurrent {
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.m, style: .continuous)
          .fill(LorvexDesign.Palette.accent.opacity(0.12))
      }
    }
    .accessibilityElement(children: .combine)
  }

  /// The time in the column the rows and the now marker share, then the
  /// marker, the title, and the duration at the trailing edge.
  private var inline: some View {
    HStack(spacing: LorvexDesign.Spacing.s + 2) {
      timeText
        .lineLimit(1)
        .frame(width: timeWidth, alignment: .leading)
      markerView
        .frame(width: 16)
      titleText
        .lineLimit(2)
      Spacer(minLength: LorvexDesign.Spacing.s)
      if let duration {
        durationText(duration)
      }
    }
  }

  /// The marker, then the time and duration over the title.
  private var stacked: some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s + 2) {
      markerView
        .frame(width: stackedMarkerWidth)
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        timeLine
        titleText
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
  }

  /// The time with the duration after it, set off by a dot, or under it
  /// where the two do not fit on one line, so neither breaks mid-word.
  @ViewBuilder private var timeLine: some View {
    if let duration {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.sm) {
          timeText
          // Without it a 24-hour time and a duration read as one run of
          // numbers ("11:00 90 min").
          Text(verbatim: "·")
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
          durationText(duration)
        }
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
          timeText
          durationText(duration)
        }
      }
    } else {
      timeText
    }
  }

  private var timeText: some View {
    Text(time)
      .font(LorvexDesign.Typography.secondaryText.monospacedDigit())
      .foregroundStyle(isCurrent ? AnyShapeStyle(LorvexDesign.Palette.accent) : AnyShapeStyle(.secondary))
  }

  private var markerView: some View {
    marker()
      .opacity(isPast ? LorvexDesign.Palette.pastMarkOpacity : 1)
  }

  private var titleText: some View {
    Text(title)
      .font(isCurrent ? LorvexDesign.Typography.primaryEmphasis : LorvexDesign.Typography.primaryText)
      .foregroundStyle(isQuiet || isPast ? Color.secondary : Color.primary)
  }

  private func durationText(_ duration: String) -> some View {
    Text(duration)
      .font(LorvexDesign.Typography.tertiaryText.monospacedDigit())
      .foregroundStyle(.secondary)
  }
}

/// Where the clock sits in a timeline: the current time in red and a hairline
/// across the column, the calendar grid's convention. `minutes` is the clock
/// the timeline was built for, minutes since midnight, so the label always
/// names the time the marker sits at; `label` is the row's accessibility
/// label ("Current time"), which callers pass localized. It follows the rows'
/// layout: its time sits in their column, and where the rows stack their time
/// above the title, the dot leads, level with the rows' markers, and the time
/// follows at its own width.
public struct LorvexTimelineNowMarker: View {
  public var minutes: Int
  public var label: String
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  /// The rows' time column, so the marker's time sits under theirs.
  @ScaledMetric(relativeTo: .subheadline) private var timeWidth = LorvexDesign.TextColumn.clockTime
  @ScaledMetric(relativeTo: .body) private var stackedMarkerWidth = LorvexTimelineMetrics.stackedMarkerWidth

  public init(minutes: Int, label: String) {
    self.minutes = minutes
    self.label = label
  }

  public var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s + 2) {
      if dynamicTypeSize.stacksTimeColumn {
        dot
          .frame(width: stackedMarkerWidth)
        // Ahead of the rule, which would otherwise take half of a narrow
        // pane and cut the time short.
        timeText
          .layoutPriority(1)
      } else {
        timeText
          .frame(width: timeWidth, alignment: .leading)
        dot
          .frame(width: 16)
      }
      Rectangle()
        .fill(LorvexDesign.Palette.nowIndicator)
        .frame(height: 1)
    }
    .padding(.horizontal, LorvexTimelineMetrics.horizontalPadding)
    .padding(.vertical, LorvexDesign.Spacing.xxs)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
  }

  private var timeText: some View {
    Text(lorvexClockTimeLabel(minutes: minutes))
      .font(LorvexDesign.Typography.tertiaryText.monospacedDigit().weight(.semibold))
      .foregroundStyle(LorvexDesign.Palette.nowIndicator)
      .lineLimit(1)
  }

  private var dot: some View {
    Circle()
      .fill(LorvexDesign.Palette.nowIndicator)
      .frame(width: 7, height: 7)
  }
}
