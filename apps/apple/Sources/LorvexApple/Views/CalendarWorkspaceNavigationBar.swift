import LorvexCore
import SwiftUI

/// The Calendar surface's in-content header: the workspace identity alone. It
/// counts nothing, since the grid shows every event and planned task itself.
/// Date navigation, the Day/Week/Month toggle, and the create action ride in
/// the window toolbar (`CalendarWorkspaceToolbar`), so the header carries no
/// subtitle and stays one line tall — the grid gets the vertical band.
struct CalendarWorkspaceHeader: View {
  var body: some View {
    WorkspacePlanHeaderChrome {
      WorkspaceHeaderIdentity(
        title: String(localized: SidebarSelection.calendar.macOSLocalizedTitle),
        subtitle: "",
        icon: "calendar",
        accessibilityIdentifier: "calendar.nav.identity"
      )
    }
  }
}

/// The Calendar toolbar: prev chevron · range chip · next chevron · a
/// "Today / This Week / This Month" jump (only while not viewing the current
/// period) in the navigation slot, the Day/Week/Month toggle in the principal
/// slot, and Create Event as the primary action. The chip opens the month
/// popover and picks a single day in every mode; in Week and Month mode it
/// shows the visible range and the owning view re-anchors to the period
/// containing the picked day. ⌘ with the arrow key that matches each chevron
/// steps the visible period, mirrored in a right-to-left layout
/// (``View/lorvexStepShortcut(_:isEnabled:)``). A toggle beside Create Event
/// shows and hides the unplanned-tasks rail (``CalendarPlanRail``).
struct CalendarWorkspaceToolbar: ToolbarContent {
  @Binding var anchorDate: Date
  @Binding var mode: CalendarPresentationMode
  @Binding var showsPlanRail: Bool
  let weekRangeTitle: String
  let monthRangeTitle: String
  let isViewingCurrent: Bool
  let step: (Int) -> Void
  let jumpToCurrent: () -> Void
  let createEvent: () -> Void

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .navigation) {
      Button {
        step(-1)
      } label: {
        Label(previousLabel, systemImage: "chevron.backward")
      }
      .help(previousLabel)
      .accessibilityIdentifier("calendar.nav.prev")
      .lorvexStepShortcut(.backward)

      LorvexDateChip(
        date: anchorDate,
        placeholder: String(localized: "calendar.field.date", defaultValue: "Date", table: "Localizable", bundle: LorvexL10n.bundle),
        displayTextOverride: rangeOverride,
        style: .toolbar,
        onSet: { anchorDate = $0 }
      )
      .accessibilityIdentifier("calendar.nav.datepicker")

      Button {
        step(1)
      } label: {
        Label(nextLabel, systemImage: "chevron.forward")
      }
      .help(nextLabel)
      .accessibilityIdentifier("calendar.nav.next")
      .lorvexStepShortcut(.forward)

      if !isViewingCurrent {
        Button(mode.currentPeriodTitle, action: jumpToCurrent)
          .accessibilityIdentifier("calendar.nav.today")
      }
    }

    ToolbarItem(placement: .principal) {
      CalendarModePicker(mode: $mode)
    }

    ToolbarItem(placement: .primaryAction) {
      Toggle(isOn: $showsPlanRail) {
        Label(CalendarPlanRailCopy.title, systemImage: "sidebar.trailing")
      }
      .toggleStyle(.button)
      .help(CalendarPlanRailCopy.title)
      .accessibilityIdentifier("calendar.planRail.toggle")
    }

    ToolbarItem(placement: .primaryAction) {
      Button(action: createEvent) {
        Label(
          String(localized: "calendar.create_event", defaultValue: "Create Event", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "plus")
      }
      .help(String(localized: "calendar.create_event", defaultValue: "Create Event", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityIdentifier("calendar.create")
    }
  }

  /// Week and Month mode show the visible range on the chip; Day mode lets the
  /// chip format the anchor date itself.
  private var rangeOverride: String? {
    switch mode {
    case .day: nil
    case .week: weekRangeTitle
    case .month: monthRangeTitle
    }
  }

  private var previousLabel: String {
    switch mode {
    case .day:
      String(localized: "calendar.nav.previous_day", defaultValue: "Previous day", table: "Localizable", bundle: LorvexL10n.bundle)
    case .week:
      String(localized: "calendar.nav.previous_week", defaultValue: "Previous week", table: "Localizable", bundle: LorvexL10n.bundle)
    case .month:
      String(localized: "calendar.nav.previous_month", defaultValue: "Previous month", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  private var nextLabel: String {
    switch mode {
    case .day:
      String(localized: "calendar.nav.next_day", defaultValue: "Next day", table: "Localizable", bundle: LorvexL10n.bundle)
    case .week:
      String(localized: "calendar.nav.next_week", defaultValue: "Next week", table: "Localizable", bundle: LorvexL10n.bundle)
    case .month:
      String(localized: "calendar.nav.next_month", defaultValue: "Next month", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

}

/// Day/Week/Month view-mode toggle.
private struct CalendarModePicker: View {
  @Binding var mode: CalendarPresentationMode

  var body: some View {
    Picker(selection: $mode) {
      ForEach(CalendarPresentationMode.allCases, id: \.self) { option in
        Text(option.title)
      }
    } label: {
      Text(CalendarPresentationMode.pickerLabel)
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .accessibilityIdentifier("calendar.viewmode")
  }
}
