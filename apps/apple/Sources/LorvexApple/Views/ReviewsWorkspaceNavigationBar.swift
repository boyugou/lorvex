import LorvexCore
import SwiftUI

/// The Reviews surface's in-content header: the workspace identity only. The
/// date navigation and the Daily/Weekly scope toggle ride in the window toolbar
/// (`ReviewsWorkspaceToolbar`), and the viewed date lives in that toolbar's
/// chip, so the identity carries no subtitle.
struct ReviewsWorkspaceHeader: View {
  var body: some View {
    WorkspacePlanHeaderChrome {
      WorkspaceHeaderIdentity(
        title: String(localized: SidebarSelection.reviews.macOSLocalizedTitle),
        subtitle: "",
        icon: SidebarSelection.reviews.systemImage,
        accessibilityIdentifier: "reviews.header.identity"
      )
    }
  }
}

/// The values the Reviews toolbar renders, read from the store once per render
/// by the owning view so the toolbar content itself holds plain data.
struct ReviewsNavigationState: Equatable {
  /// The day the chip's month popover opens on: the selected day in Daily
  /// scope, the viewed week's anchor day (its final day) in Weekly scope.
  let chipDate: Date?
  /// The viewed week's `"YYYY-MM-DD - YYYY-MM-DD"` window rendered as a
  /// localized day range ("Jun 18 – 24"), with its years when the week is not
  /// within the current year.
  let weekRangeTitle: String
  /// Whether the viewed day (Daily) or week (Weekly) is the current one.
  let isViewingCurrent: Bool

  @MainActor
  init(store: AppStore, mode: ReviewMode) {
    let key = mode == .daily
      ? store.selectedReviewDate
      : (store.weeklyReviewAnchor ?? store.logicalTodayDateString)
    chipDate = LorvexDateFormatters.ymd.date(from: key)
    weekRangeTitle = ReviewsWeekRangeFormatter.format(
      store.weeklyReview?.windowTitle ?? "",
      now: LorvexDateFormatters.ymd.date(from: store.logicalTodayDateString) ?? Date())
    isViewingCurrent = mode == .daily ? store.isViewingCurrentDay : store.isViewingCurrentWeek
  }
}

/// The Reviews toolbar: prev chevron · date chip · next chevron · a
/// "Today / This Week" jump (only while not viewing the current period) in the
/// navigation slot, and the Daily/Weekly scope toggle in the principal slot.
/// Daily scope picks/steps a single day; Weekly scope shows the viewed week's
/// range on the same single-day chip (picking any day jumps to its week) and
/// steps week-to-week. Reuses the Calendar nav localization keys.
///
/// `store` is used for the mutations only; everything rendered comes from
/// `state`, which the owning view derives on each render.
struct ReviewsWorkspaceToolbar: ToolbarContent {
  let store: AppStore
  let state: ReviewsNavigationState
  @Binding var mode: ReviewMode
  /// ⌘ with the arrow key that matches each chevron steps the period,
  /// mirrored in a right-to-left layout
  /// (``View/lorvexStepShortcut(_:isEnabled:)``), unless the daily editor
  /// holds keyboard focus.
  var dayStepShortcutsEnabled = true

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .navigation) {
      Button {
        Task { await step(-1) }
      } label: {
        Label(previousLabel, systemImage: "chevron.backward")
      }
      .help(previousLabel)
      .accessibilityIdentifier("reviews.nav.prev")
      .lorvexStepShortcut(.backward, isEnabled: dayStepShortcutsEnabled)

      LorvexDateChip(
        date: state.chipDate,
        placeholder: String(localized: "calendar.field.date", defaultValue: "Date", table: "Localizable", bundle: LorvexL10n.bundle),
        displayTextOverride: mode == .weekly ? state.weekRangeTitle : nil,
        style: .toolbar,
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
      .accessibilityIdentifier("reviews.nav.datepicker")

      Button {
        Task { await step(1) }
      } label: {
        Label(nextLabel, systemImage: "chevron.forward")
      }
      .help(nextLabel)
      .accessibilityIdentifier("reviews.nav.next")
      .lorvexStepShortcut(.forward, isEnabled: dayStepShortcutsEnabled)
      // Both scopes clamp forward at the current period: Daily can't step past
      // today, Weekly can't step past the current week (this also disables the
      // forward shortcut).
      .disabled(state.isViewingCurrent)

      if !state.isViewingCurrent {
        Button(currentLabel) { Task { await jumpToCurrent() } }
          .accessibilityIdentifier("reviews.nav.current")
      }
    }

    ToolbarItem(placement: .principal) {
      ReviewModePicker(mode: $mode)
    }
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

/// The Daily/Weekly scope toggle — the same `ReviewMode` switch that drives
/// the workspace's two columns.
struct ReviewModePicker: View {
  @Binding var mode: ReviewMode

  var body: some View {
    Picker(selection: $mode) {
      Text(String(localized: "reviews.mode.daily", defaultValue: "Daily", table: "Localizable", bundle: LorvexL10n.bundle))
        .tag(ReviewMode.daily)
      Text(String(localized: "reviews.mode.weekly", defaultValue: "Weekly", table: "Localizable", bundle: LorvexL10n.bundle))
        .tag(ReviewMode.weekly)
    } label: {
      Text(String(localized: "reviews.mode.picker", defaultValue: "Review", table: "Localizable", bundle: LorvexL10n.bundle))
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .accessibilityIdentifier("reviews.mode.picker")
  }
}

/// Renders the core's `"YYYY-MM-DD - YYYY-MM-DD"` weekly window as a localized
/// day range ("Jun 18 – 24"), with its years once the window reaches outside
/// `now`'s year (``LorvexDateFormatters/dayRange(from:to:now:calendar:locale:)``),
/// falling back to the raw title when it can't be parsed.
enum ReviewsWeekRangeFormatter {
  static func format(_ windowTitle: String, now: Date) -> String {
    let parts = windowTitle.components(separatedBy: " - ")
    guard parts.count == 2,
      let start = LorvexDateFormatters.ymd.date(from: parts[0]),
      let end = LorvexDateFormatters.ymd.date(from: parts[1])
    else { return windowTitle }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    return LorvexDateFormatters.dayRange(from: start, to: end, now: now, calendar: calendar)
  }
}
