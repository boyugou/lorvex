import LorvexCore
import SwiftUI

struct CalendarWorkspaceNavigationBar: View {
  @Binding var anchorDate: Date
  @Binding var mode: CalendarPresentationMode

  let weekRangeTitle: String
  let monthRangeTitle: String
  let isViewingCurrent: Bool
  let eventCount: Int
  let plannedTaskCount: Int
  let isFiltering: Bool
  let step: (Int) -> Void
  let jumpToCurrent: () -> Void
  private let actions: AnyView

  init<Actions: View>(
    anchorDate: Binding<Date>,
    mode: Binding<CalendarPresentationMode>,
    weekRangeTitle: String,
    monthRangeTitle: String,
    isViewingCurrent: Bool,
    eventCount: Int,
    plannedTaskCount: Int,
    isFiltering: Bool,
    step: @escaping (Int) -> Void,
    jumpToCurrent: @escaping () -> Void,
    @ViewBuilder actions: () -> Actions
  ) {
    self._anchorDate = anchorDate
    self._mode = mode
    self.weekRangeTitle = weekRangeTitle
    self.monthRangeTitle = monthRangeTitle
    self.isViewingCurrent = isViewingCurrent
    self.eventCount = eventCount
    self.plannedTaskCount = plannedTaskCount
    self.isFiltering = isFiltering
    self.step = step
    self.jumpToCurrent = jumpToCurrent
    self.actions = AnyView(actions())
  }

  private var hasVisibleSignals: Bool {
    !navigationSignals.isEmpty
  }

  var body: some View {
    WorkspacePlanHeaderChrome {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        // Large in-content title (the date chip + picker below carry the range,
        // so the title needs no subtitle), with the workspace actions trailing.
        HStack(alignment: .center, spacing: LorvexDesign.Spacing.m) {
          WorkspaceHeaderIdentity(
            title: String(localized: SidebarSelection.calendar.macOSLocalizedTitle),
            subtitle: "",
            systemImage: "calendar",
            accessibilityIdentifier: "calendar.nav.identity"
          )

          Spacer(minLength: LorvexDesign.Spacing.m)

          actionCluster
        }

        // Compact control row. The date-navigation cluster has a fixed width so
        // its trailing edge — and therefore the view-mode switcher right after
        // it — never shifts when the label changes between the day's single date
        // and the week's range.
        HStack(alignment: .center, spacing: LorvexDesign.Spacing.s) {
          CalendarRangeControl(
            mode: mode,
            anchorDate: $anchorDate,
            rangeTitle: rangeControlTitle,
            isViewingCurrent: isViewingCurrent,
            previousLabel: previousLabel,
            nextLabel: nextLabel,
            currentLabel: currentLabel,
            step: step,
            jumpToCurrent: jumpToCurrent
          )
          .frame(width: 320, alignment: .leading)

          CalendarModePicker(mode: $mode)

          if hasVisibleSignals {
            CalendarNavigationSignalStrip(signals: navigationSignals)
          }

          Spacer(minLength: 0)
        }
        .accessibilityIdentifier("calendar.nav.contextRow")
      }
    }
  }

  private var actionCluster: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      actions
    }
    .fixedSize(horizontal: true, vertical: false)
    .accessibilityIdentifier("calendar.nav.actions")
  }

  private var navigationSignals: [CalendarNavigationSignal] {
    var signals: [CalendarNavigationSignal] = []
    if eventCount > 0 {
      signals.append(CalendarNavigationSignal(
        id: "events",
        title: String(localized: "calendar.header.events_label", defaultValue: "Events", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(eventCount)",
        systemImage: "calendar",
        tint: .blue
      ))
    }
    if plannedTaskCount > 0 {
      signals.append(CalendarNavigationSignal(
        id: "planned",
        title: String(localized: "calendar.header.planned_label", defaultValue: "Planned", table: "Localizable", bundle: LorvexL10n.bundle),
        value: "\(plannedTaskCount)",
        systemImage: "checklist",
        tint: .orange
      ))
    }
    if isFiltering {
      signals.append(CalendarNavigationSignal(
        id: "filtered",
        title: String(localized: "calendar.header.filtered", defaultValue: "Filtered", table: "Localizable", bundle: LorvexL10n.bundle),
        value: nil,
        systemImage: "line.3.horizontal.decrease.circle",
        tint: .secondary
      ))
    }
    return signals
  }

  private var rangeControlTitle: String {
    switch mode {
    case .day:
      Self.dateFormatter.string(from: anchorDate)
    case .week:
      weekRangeTitle
    case .month:
      monthRangeTitle
    }
  }

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()

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

  private var currentLabel: String {
    switch mode {
    case .day:
      String(localized: "calendar.nav.today", defaultValue: "Today", table: "Localizable", bundle: LorvexL10n.bundle)
    case .week:
      String(localized: "calendar.nav.this_week", defaultValue: "This Week", table: "Localizable", bundle: LorvexL10n.bundle)
    case .month:
      String(localized: "calendar.nav.this_month", defaultValue: "This Month", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}

private struct CalendarNavigationSignal: Identifiable {
  let id: String
  let title: String
  let value: String?
  let systemImage: String
  let tint: Color
}

private struct CalendarNavigationSignalStrip: View {
  let signals: [CalendarNavigationSignal]

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      ForEach(signals) { signal in
        CalendarNavigationSignalBadge(signal: signal)
      }
    }
    .accessibilityIdentifier("calendar.nav.signals")
  }
}

private struct CalendarNavigationSignalBadge: View {
  let signal: CalendarNavigationSignal

  var body: some View {
    Label {
      HStack(spacing: 4) {
        if let value = signal.value {
          Text(value)
            .font(LorvexDesign.Typography.tertiaryText.monospacedDigit().weight(.semibold))
        }
        Text(signal.title)
          .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
      }
      .lineLimit(1)
    } icon: {
      Image(systemName: signal.systemImage)
        .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
    }
    .foregroundStyle(signal.tint)
    .padding(.horizontal, LorvexDesign.Spacing.xs)
    .padding(.vertical, 3)
    .background(signal.tint.opacity(0.10), in: Capsule())
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("calendar.nav.signal.\(signal.id)")
  }
}

/// Day/Week/Month view-mode toggle, rendered as the shared rounded capsule
/// control.
private struct CalendarModePicker: View {
  @Binding var mode: CalendarPresentationMode

  var body: some View {
    LorvexSegmentedControl(
      options: [.day, .week, .month],
      selection: $mode,
      title: { value in
        switch value {
        case .day:
          String(localized: "calendar.mode.day", defaultValue: "Day", table: "Localizable", bundle: LorvexL10n.bundle)
        case .week:
          String(localized: "calendar.mode.week", defaultValue: "Week", table: "Localizable", bundle: LorvexL10n.bundle)
        case .month:
          String(localized: "calendar.mode.month", defaultValue: "Month", table: "Localizable", bundle: LorvexL10n.bundle)
        }
      },
      accessibilityIdentifier: "calendar.viewmode",
      accessibilityLabel: String(
        localized: "calendar.nav.view_mode.a11y", defaultValue: "Calendar view mode",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    )
  }
}

private struct CalendarRangeControl: View {
  let mode: CalendarPresentationMode
  @Binding var anchorDate: Date
  let rangeTitle: String
  let isViewingCurrent: Bool
  let previousLabel: String
  let nextLabel: String
  let currentLabel: String
  let step: (Int) -> Void
  let jumpToCurrent: () -> Void

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Button {
        step(-1)
      } label: {
        Image(systemName: "chevron.left")
      }
      .help(previousLabel)
      .accessibilityLabel(previousLabel)
      .accessibilityIdentifier("calendar.nav.prev")
      .keyboardShortcut(.leftArrow, modifiers: [.command])

      dateWindowControl

      Button {
        step(1)
      } label: {
        Image(systemName: "chevron.right")
      }
      .help(nextLabel)
      .accessibilityLabel(nextLabel)
      .accessibilityIdentifier("calendar.nav.next")
      .keyboardShortcut(.rightArrow, modifiers: [.command])

      if !isViewingCurrent {
        Button(currentLabel, action: jumpToCurrent)
          .buttonStyle(.bordered)
          .controlSize(.small)
          .accessibilityIdentifier("calendar.nav.today")
      }
    }
    .controlSize(.small)
    .buttonBorderShape(.roundedRectangle(radius: LorvexDesign.Radius.s))
    .accessibilityIdentifier("calendar.nav.rangeControl")
  }

  @ViewBuilder
  private var dateWindowControl: some View {
    // One shared calendar chip for every mode (graphical month popover), not
    // the stock stepper; the anchor always has a value, so no clear action. In
    // week/month mode the chip shows the range but still picks a single day —
    // choosing any day jumps to the week/month containing it.
    LorvexDateChip(
      date: anchorDate,
      placeholder: String(
        localized: "calendar.field.date", defaultValue: "Date",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      displayTextOverride: mode == .day ? nil : rangeTitle,
      onSet: { anchorDate = $0 }
    )
    .fixedSize()
    .frame(minWidth: 150, alignment: .leading)
    .accessibilityIdentifier("calendar.nav.datepicker")
  }
}
