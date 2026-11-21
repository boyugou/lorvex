import LorvexCore
import SwiftUI

/// Week navigation stays in the same place when the person switches between
/// the timetable and its chronological agenda. A short window or larger type
/// moves the controls below the date range.
struct MobileCalendarWeekHeader: View {
  let title: String
  let showsAgenda: Bool
  @Binding var offset: Int
  let pageRange: ClosedRange<Int>
  let goToToday: () -> Void
  let toggleLayout: () -> Void

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: LorvexDesign.Spacing.m) {
        dateTitle.fixedSize(horizontal: true, vertical: true)
        Spacer(minLength: 0)
        controls
      }
      VStack(alignment: .leading, spacing: 0) {
        dateTitle
        controls
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, LorvexDesign.Spacing.m)
  }

  private var dateTitle: some View {
    Text(title)
      .font(LorvexDesign.Typography.primaryEmphasis)
      .accessibilityAddTraits(.isHeader)
      .accessibilityIdentifier("mobileCalendar.header")
  }

  private var controls: some View {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      Button {
        offset -= 1
      } label: {
        Image(systemName: "chevron.backward").frame(minWidth: 44, minHeight: 44)
      }
      .disabled(offset <= pageRange.lowerBound)
      .accessibilityLabel(
        String(
          localized: "calendar.nav.previous_week", defaultValue: "Previous week",
          table: "Localizable", bundle: MobileL10n.bundle)
      )
      .accessibilityIdentifier("mobileCalendar.week.previous")
      Button {
        offset += 1
      } label: {
        Image(systemName: "chevron.forward").frame(minWidth: 44, minHeight: 44)
      }
      .disabled(offset >= pageRange.upperBound)
      .accessibilityLabel(
        String(
          localized: "calendar.nav.next_week", defaultValue: "Next week", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      .accessibilityIdentifier("mobileCalendar.week.next")
      if offset != 0 {
        Button(
          String(
            localized: "calendar.today", defaultValue: "Today", table: "Localizable",
            bundle: MobileL10n.bundle), action: goToToday
        )
        .accessibilityIdentifier("mobileCalendar.today")
      }
      Button(action: toggleLayout) {
        ViewThatFits(in: .horizontal) {
          Label(layoutTitle, systemImage: layoutSymbol)
            .fixedSize(horizontal: true, vertical: false)
          Image(systemName: layoutSymbol)
        }
        .frame(minWidth: 44, minHeight: 44)
      }
      .accessibilityLabel(layoutTitle)
      .accessibilityIdentifier("mobileCalendar.week.layout")
    }
    .buttonStyle(.borderless)
  }

  private var layoutSymbol: String { showsAgenda ? "calendar" : "list.bullet" }

  private var layoutTitle: String {
    if showsAgenda {
      String(
        localized: "calendar.week.time_grid", defaultValue: "Time grid", table: "Localizable",
        bundle: MobileL10n.bundle)
    } else {
      String(
        localized: "calendar.agenda", defaultValue: "Agenda", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }
}
