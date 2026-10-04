import LorvexCore
import SwiftUI

/// The calendar's navigation-bar items, the same in every mode: the Day /
/// Week / Month picker in the bar's center, standing in for the inline title
/// the tab bar already gives, and New Event. In a compact width (a phone)
/// New Event stands at the bar's leading edge, which leaves the center room
/// for three segments in every language; in a regular width it stands with
/// the bar's trailing items.
struct MobileCalendarToolbar: ToolbarContent {
  let mode: MobileCalendarPresentationMode
  /// The days Day mode shows at the current width, which name its segment
  /// ("Day", "3 Days").
  let gridDayCount: Int
  let isCompactWidth: Bool
  let switchMode: (MobileCalendarPresentationMode) -> Void
  let createEvent: () -> Void

  var body: some ToolbarContent {
    ToolbarItem(placement: .principal) {
      Picker(
        String(
          localized: "calendar.view_picker", defaultValue: "View", table: "Localizable",
          bundle: MobileL10n.bundle),
        selection: Binding(get: { mode }, set: { switchMode($0) })
      ) {
        ForEach(MobileCalendarPresentationMode.allCases) { mode in
          Text(mode.title(gridDayCount: gridDayCount)).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      // A segmented control in the toolbar keeps the titles it was created
      // with, so it is rebuilt whenever the grid's day count renames a segment.
      .id(gridDayCount)
      .frame(maxWidth: 300)
      .accessibilityIdentifier("mobileCalendar.presentationToggle")
    }
    #if os(iOS)
      if isCompactWidth {
        ToolbarItem(placement: .topBarLeading) { newEventButton }
      } else {
        ToolbarItem(placement: .primaryAction) { newEventButton }
      }
    #else
      ToolbarItem(placement: .primaryAction) { newEventButton }
    #endif
  }

  /// The tab bar's plus captures a task; New Event carries the calendar glyph
  /// so the two creation buttons never read as the same action.
  private var newEventButton: some View {
    Button(action: createEvent) {
      Label(
        String(
          localized: "calendar.new_event", defaultValue: "New Event", table: "Localizable",
          bundle: MobileL10n.bundle), systemImage: "calendar.badge.plus")
    }
    .lorvexToolbarHoverEffect()
    .accessibilityIdentifier("mobileCalendar.toolbarCreate")
  }
}

/// The row over a calendar grid: what the grid shows (a month, or a week's
/// range), then Today. Today keeps its slot while it has nothing to do, only
/// hidden, so the title never shifts when the user pages away and the button
/// appears.
struct MobileCalendarHeaderRow: View {
  let title: String
  /// Whether Today has nothing to do: today is in view, and in Month mode
  /// also chosen.
  let isOnToday: Bool
  let goToToday: () -> Void

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      Text(title)
        .font(LorvexDesign.Typography.primaryEmphasis)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityAddTraits(.isHeader)
        .contentTransition(.numericText())
      Spacer(minLength: 0)
      Button(
        String(
          localized: "calendar.today", defaultValue: "Today", table: "Localizable",
          bundle: MobileL10n.bundle),
        action: goToToday
      )
      .buttonStyle(.bordered)
      .controlSize(.small)
      .opacity(isOnToday ? 0 : 1)
      .disabled(isOnToday)
      .accessibilityHidden(isOnToday)
      .accessibilityIdentifier("mobileCalendar.today")
    }
    .padding(.horizontal, LorvexDesign.Spacing.l)
    .padding(.top, LorvexDesign.Spacing.xs)
    .reduceMotionAnimation(.snappy(duration: 0.2), value: isOnToday)
    .accessibilityIdentifier("mobileCalendar.header")
  }
}
