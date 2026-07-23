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
        .accessibilityLabel(accessibleDate(day))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
  }

  private func isToday(_ date: Date) -> Bool { calendar.isDateInToday(date) }

  private func weekdaySymbol(_ date: Date) -> String {
    MobileDateFormatting.weekdayAbbrev.string(from: date)
      .uppercased(with: MobileL10n.locale)
  }

  private func dayNumber(_ date: Date) -> String {
    MobileDateFormatting.dayOfMonth.string(from: date)
  }

  private func accessibleDate(_ date: Date) -> String {
    let base = Self.fullDateFormatter.string(from: date)
    guard isToday(date) else { return base }
    return String(
      format: String(
        localized: "calendar.week.today_prefix", defaultValue: "Today, %@", table: "Localizable",
        bundle: MobileL10n.bundle), base)
  }

  private static let fullDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = MobileL10n.locale
    f.dateStyle = .full
    return f
  }()
}
