import LorvexCore
import SwiftUI

/// A calendar event in the menu bar panel, on Today and on Next 7 Days: a bar
/// in its calendar's color where a task row has its circle, the title (up to
/// two lines, as a task's), and its time on the day it is listed under.
/// Clicking it opens the event's detail in the main window.
///
/// The time is the event's range on that day ("1:00 – 1:30 PM"); one day of an
/// event that runs past midnight reads its start on the first day and
/// "Until 1:30 AM" on the last, and an event with no place on the day's clock
/// reads "All day".
struct MenuBarEventRow: View {
  let event: CalendarTimelineEvent
  /// The day the row is listed under, as `yyyy-MM-dd`.
  let dayKey: String
  /// Names the row for UI tests.
  let identifier: String
  let open: () -> Void

  var body: some View {
    Button(action: open) {
      HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
        Capsule()
          .fill(Color(lorvexHex: event.color) ?? LorvexDesign.Palette.neutral)
          .frame(width: 3, height: 14)
          .frame(width: 18)
          // The bar sits on the title's first line, centered on its capital
          // letters, as a task's circle does.
          .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
          .accessibilityHidden(true)
        Text(userContent: event.title)
          .font(LorvexDesign.Typography.primaryText)
          .foregroundStyle(.primary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        Text(time)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .lineLimit(1)
          .fixedSize()
      }
      .padding(.vertical, LorvexDesign.Spacing.sm)
      .frame(minHeight: MenuBarTaskRow.minHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(TodayCalmCopy.openDetails)
    .accessibilityIdentifier(identifier)
  }

  private var time: String {
    event.listTimeLabel(on: dayKey, range: TodayCalmCopy.timeRange(start:end:)) ?? TodayCalmCopy.allDay
  }
}
