import LorvexCore
import SwiftUI

@MainActor
struct MobileCalendarWeekStrip: View {
  let visibleDate: Date
  let calendar: Calendar
  let selectDay: (Date) -> Void

  var body: some View {
    let weekStart = CalendarGridModel.startOfWeek(containing: visibleDate, calendar: calendar)
    HStack(spacing: 0) {
      ForEach(0..<7, id: \.self) { index in
        let day = calendar.date(byAdding: .day, value: index, to: weekStart) ?? weekStart
        let selected = calendar.isDate(day, inSameDayAs: visibleDate)
        Button {
          selectDay(day)
        } label: {
          VStack(spacing: 3) {
            Text(weekdaySymbol(day))
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.secondary)
            Text(dayNumber(day))
              .font(LorvexDesign.Typography.secondaryText.weight(selected ? .bold : .regular))
              .foregroundStyle(
                selected
                  ? AnyShapeStyle(.background)
                  : (isToday(day) ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
              )
              .frame(width: 30, height: 30)
              .background {
                if selected {
                  Circle().fill(.tint)
                } else if isToday(day) {
                  Circle().stroke(.tint, lineWidth: 1)
                }
              }
          }
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          MobileCalendarDayName.spoken(day, isToday: isToday(day), calendar: calendar)
        )
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
  }

  private func isToday(_ date: Date) -> Bool { calendar.isDateInToday(date) }

  private func weekdaySymbol(_ date: Date) -> String {
    LorvexDateFormatters.string(date, template: "EEE", timeZone: calendar.timeZone)
  }

  private func dayNumber(_ date: Date) -> String {
    LorvexDateFormatters.dayNumber(date, timeZone: calendar.timeZone)
  }
}

/// The week strip as a horizontal pager of weeks. Swiping it follows the finger
/// and can reverse mid-way; when another week settles, the visible day moves by
/// whole weeks and keeps its weekday, as in Apple Calendar. While a swipe is in
/// flight every week shows that weekday selected, so the strip previews where
/// the day lands. Weeks count from the one containing `today`.
@MainActor
struct MobileCalendarWeekStripPager: View {
  let visibleDate: Date
  let today: Date
  let calendar: Calendar
  /// The weeks the pager reaches either side of today's week.
  let weekRange: ClosedRange<Int>
  let selectDay: (Date) -> Void

  @State private var scrolledWeek: Int?

  var body: some View {
    ScrollView(.horizontal) {
      LazyHStack(spacing: 0) {
        ForEach(weekRange, id: \.self) { week in
          MobileCalendarWeekStrip(
            visibleDate: sameWeekday(inWeek: week), calendar: calendar, selectDay: selectDay
          )
          .containerRelativeFrame(.horizontal)
          // The weeks beside the visible one are only there to be swiped to,
          // each with its own copy of the selected weekday. VoiceOver reaches
          // the visible week alone, and moves weeks with its scroll gesture.
          .accessibilityHidden(week != visibleWeek)
        }
      }
      .scrollTargetLayout()
    }
    .scrollTargetBehavior(.paging)
    .scrollIndicators(.hidden)
    // A horizontal scroll view takes every point of height it is offered; the
    // strip keeps its own.
    .fixedSize(horizontal: false, vertical: true)
    .scrollPosition(id: $scrolledWeek)
    .onAppear { scrolledWeek = visibleWeek }
    .onChange(of: visibleWeek) { _, week in
      guard scrolledWeek != week else { return }
      lorvexAnimated(.snappy) { scrolledWeek = week }
    }
    .onChange(of: scrolledWeek) { previous, week in
      // The first position, which the strip takes as it appears, is no swipe:
      // the visible day may move in the same update, and reading that first
      // position against the moved day would select the week it left.
      guard previous != nil, let week, week != visibleWeek else { return }
      selectDay(sameWeekday(inWeek: week))
    }
  }

  private var todayWeekStart: Date {
    CalendarGridModel.startOfWeek(containing: today, calendar: calendar)
  }

  private var visibleWeek: Int {
    let start = CalendarGridModel.startOfWeek(containing: visibleDate, calendar: calendar)
    let days = calendar.dateComponents([.day], from: todayWeekStart, to: start).day ?? 0
    return Int((Double(days) / 7).rounded())
  }

  private func sameWeekday(inWeek week: Int) -> Date {
    calendar.date(byAdding: .day, value: (week - visibleWeek) * 7, to: visibleDate) ?? visibleDate
  }
}
