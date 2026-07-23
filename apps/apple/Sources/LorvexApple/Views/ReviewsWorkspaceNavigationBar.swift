import LorvexCore
import SwiftUI

/// The Reviews surface's header + date-navigation control row. Mirrors the
/// Calendar workspace's nav: a blue-icon identity title, then a compact row of
/// prev chevron · `LorvexDateChip` · next chevron · a "today / this week"
/// button (only when not viewing the current day/week), followed by the
/// Daily/Weekly scope toggle. The chip and chevrons drive whichever scope is
/// active; the date itself lives in the chip, so the identity carries no
/// subtitle.
struct ReviewsWorkspaceNavigationBar: View {
  @Bindable var store: AppStore
  @Binding var mode: ReviewMode
  var dayStepShortcutsEnabled = true

  var body: some View {
    WorkspacePlanHeaderChrome {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        WorkspaceHeaderIdentity(
          title: String(localized: SidebarSelection.reviews.macOSLocalizedTitle),
          subtitle: "",
          systemImage: SidebarSelection.reviews.systemImage,
          accessibilityIdentifier: "reviews.header.identity"
        )

        // Compact control row. The date-navigation cluster has a fixed width so
        // its trailing edge — and the Daily/Weekly toggle right after it — never
        // shifts when the chip label changes between a single day and a week
        // range.
        HStack(alignment: .center, spacing: LorvexDesign.Spacing.s) {
          ReviewsRangeControl(
            store: store,
            mode: mode,
            shortcutsEnabled: dayStepShortcutsEnabled
          )
            .frame(width: 320, alignment: .leading)

          ReviewModePicker(mode: $mode)

          Spacer(minLength: 0)
        }
        .accessibilityIdentifier("reviews.nav.contextRow")
      }
    }
  }
}

/// The Daily/Weekly scope toggle, rendered as the shared rounded capsule
/// control — the same `ReviewMode` switch that drives the workspace's two
/// columns.
struct ReviewModePicker: View {
  @Binding var mode: ReviewMode

  var body: some View {
    LorvexSegmentedControl(
      options: [.daily, .weekly],
      selection: $mode,
      title: { value in
        value == .daily
          ? String(localized: "reviews.mode.daily", defaultValue: "Daily", table: "Localizable", bundle: LorvexL10n.bundle)
          : String(localized: "reviews.mode.weekly", defaultValue: "Weekly", table: "Localizable", bundle: LorvexL10n.bundle)
      },
      accessibilityIdentifier: "reviews.mode.picker",
      accessibilityLabel: String(localized: "reviews.mode.picker", defaultValue: "Review", table: "Localizable", bundle: LorvexL10n.bundle)
    )
  }
}

/// Prev chevron · date chip · next chevron · a current-period jump button.
/// Daily scope picks/steps a single day; Weekly scope shows the viewed week's
/// range on the same single-day chip (picking any day jumps to its week) and
/// steps week-to-week. Reuses the Calendar nav localization keys.
private struct ReviewsRangeControl: View {
  @Bindable var store: AppStore
  let mode: ReviewMode
  let shortcutsEnabled: Bool

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Button {
        Task { await step(-1) }
      } label: {
        Image(systemName: "chevron.left")
      }
      .help(previousLabel)
      .accessibilityLabel(previousLabel)
      .accessibilityIdentifier("reviews.nav.prev")
      .reviewNavigationShortcut(.leftArrow, enabled: shortcutsEnabled)

      dateChip

      Button {
        Task { await step(1) }
      } label: {
        Image(systemName: "chevron.right")
      }
      .help(nextLabel)
      .accessibilityLabel(nextLabel)
      .accessibilityIdentifier("reviews.nav.next")
      .reviewNavigationShortcut(.rightArrow, enabled: shortcutsEnabled)
      // Both scopes clamp forward at the current period: Daily can't step past
      // today, Weekly can't step past the current week (also disables ⌘→).
      .disabled(isViewingCurrent)

      if !isViewingCurrent {
        Button(currentLabel) { Task { await jumpToCurrent() } }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .accessibilityIdentifier("reviews.nav.current")
      }
    }
    .controlSize(.small)
    .buttonBorderShape(.roundedRectangle(radius: LorvexDesign.Radius.s))
    .accessibilityIdentifier("reviews.nav.rangeControl")
  }

  @ViewBuilder
  private var dateChip: some View {
    // One shared calendar chip for both scopes (graphical month popover). In
    // Week scope the chip shows the week range but still picks a single day —
    // choosing any day jumps to the week containing it.
    LorvexDateChip(
      date: chipDate,
      placeholder: String(localized: "calendar.field.date", defaultValue: "Date", table: "Localizable", bundle: LorvexL10n.bundle),
      displayTextOverride: mode == .weekly ? weekRangeTitle : nil,
      onSet: { picked in
        let day = LorvexDateFormatters.ymd.string(from: picked)
        Task {
          switch mode {
          case .daily: await store.selectReviewDay(day)
          case .weekly: await store.selectReviewWeek(of: day)
          }
        }
      }
    )
    .fixedSize()
    .frame(minWidth: 150, alignment: .leading)
    .accessibilityIdentifier("reviews.nav.datepicker")
  }

  /// The day the chip's month popover opens on: the selected day in Day scope,
  /// the viewed week's anchor day (its final day) in Week scope.
  private var chipDate: Date? {
    let key = mode == .daily
      ? store.selectedReviewDate
      : (store.weeklyReviewAnchor ?? store.logicalTodayDateString)
    return LorvexDateFormatters.ymd.date(from: key)
  }

  private func step(_ delta: Int) async {
    switch mode {
    case .daily: await store.stepReviewDay(by: delta)
    case .weekly: await store.stepWeeklyReview(byWeeks: delta)
    }
  }

  private func jumpToCurrent() async {
    switch mode {
    case .daily: await store.selectReviewDay(store.logicalTodayDateString)
    case .weekly: await store.jumpWeeklyReviewToCurrentWeek()
    }
  }

  private var isViewingCurrent: Bool {
    mode == .daily ? store.isViewingCurrentDay : store.isViewingCurrentWeek
  }

  /// The viewed week's `"YYYY-MM-DD - YYYY-MM-DD"` window rendered as a
  /// localized month/day range (e.g. "Jun 18 – Jun 24"), falling back to the
  /// raw title when it can't be parsed.
  private var weekRangeTitle: String {
    ReviewsWeekRangeFormatter.format(store.weeklyReview?.windowTitle ?? "")
  }

  private var previousLabel: String {
    mode == .daily
      ? String(localized: "calendar.nav.previous_day", defaultValue: "Previous day", table: "Localizable", bundle: LorvexL10n.bundle)
      : String(localized: "calendar.nav.previous_week", defaultValue: "Previous week", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  private var nextLabel: String {
    mode == .daily
      ? String(localized: "calendar.nav.next_day", defaultValue: "Next day", table: "Localizable", bundle: LorvexL10n.bundle)
      : String(localized: "calendar.nav.next_week", defaultValue: "Next week", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  private var currentLabel: String {
    mode == .daily
      ? String(localized: "calendar.nav.today", defaultValue: "Today", table: "Localizable", bundle: LorvexL10n.bundle)
      : String(localized: "calendar.nav.this_week", defaultValue: "This Week", table: "Localizable", bundle: LorvexL10n.bundle)
  }
}

private extension View {
  @ViewBuilder
  func reviewNavigationShortcut(_ key: KeyEquivalent, enabled: Bool) -> some View {
    if enabled {
      keyboardShortcut(key, modifiers: [.command])
    } else {
      self
    }
  }
}

/// Renders the core's `"YYYY-MM-DD - YYYY-MM-DD"` weekly window as a localized
/// month/day range (e.g. "Jun 18 – Jun 24"), falling back to the raw title when
/// it can't be parsed.
enum ReviewsWeekRangeFormatter {
  static func format(_ windowTitle: String) -> String {
    let parts = windowTitle.components(separatedBy: " - ")
    guard parts.count == 2,
      let start = LorvexDateFormatters.ymd.date(from: parts[0]),
      let end = LorvexDateFormatters.ymd.date(from: parts[1])
    else { return windowTitle }
    let formatter = LorvexMonthDayFormatter.local
    return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
  }
}
