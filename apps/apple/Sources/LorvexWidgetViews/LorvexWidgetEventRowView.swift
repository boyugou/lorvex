import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI
import WidgetKit

/// One of the day's calendar events under the large Today widget's tasks, as
/// the app's schedule draws an event: a thin bar in the event's color where a
/// task has its circle, since an event is not the person's to complete, then
/// its title, and its time at the trailing edge in the column a task's time
/// takes ("2:00 PM", "Until 3:00 PM" in the accent while it runs, "All day").
/// The row opens the calendar.
///
/// The bar stands in a column as wide as a task's circle and centered on it,
/// on the lead ring's axis under a lead task, so the titles start where the
/// tasks' titles do. A row is shorter than a task's, which is as tall as its
/// complete button; an event has no button.
struct WidgetEventRowView: View {
  let row: WidgetEventRenderRow
  var leadRingDiameter: CGFloat?
  @ScaledMetric(relativeTo: WidgetType.rowTextStyle) private var circleColumn = widgetRowHeight
  @ScaledMetric(relativeTo: WidgetType.rowTextStyle) private var height: CGFloat = 24

  var body: some View {
    HStack(spacing: leadRingDiameter == nil ? 0 : 12) {
      bar
        .frame(
          width: leadRingDiameter ?? circleColumn,
          alignment: leadRingDiameter == nil ? .leading : .center)
      Link(destination: LorvexDeepLinkContract.destinationURL(.calendar)) { label }
    }
    .frame(height: height)
  }

  /// A circle glyph's footprint, hidden, with the bar at its center, so the
  /// bar sits where a task row's circle does at every text size.
  private var bar: some View {
    Image(systemName: "circle")
      .font(WidgetType.row)
      .imageScale(.large)
      .hidden()
      .overlay {
        Capsule()
          .fill(LorvexDesign.Palette.eventTint(row.color))
          .frame(width: 3)
          .padding(.vertical, 2)
          .widgetAccentable()
      }
      .accessibilityHidden(true)
  }

  private var label: some View {
    // Absolute colors: the enclosing `Link` sets the foreground to the
    // accent, as on a task row.
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(userContent: row.title)
        .font(WidgetType.row)
        .foregroundStyle(Color.primary)
        .lineLimit(1)
        .privacySensitive()
      Spacer(minLength: 0)
      Text(row.timeLabel)
        .font(WidgetType.meta)
        .foregroundStyle(row.tone == .running ? LorvexDesign.Palette.accent : Color.secondary)
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(row.title), \(row.timeLabel)")
  }
}
