import LorvexCore
import SwiftUI

struct MobileStoreTodayView: View {
  @Bindable var store: MobileStore
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @State private var editingHabit: LorvexHabit?
  @State private var editingCalendarEvent: CalendarTimelineEvent?
  /// iPhone shows the day's schedule as a sheet opened from the day strip.
  @State private var isShowingSchedule = false

  var body: some View {
    content
    #if DEBUG
      .task { await suggestTimesForPreviewIfRequested() }
    #endif
  }

  /// iPhone reads the Today list alone and opens the schedule as a sheet from
  /// the day strip. Regular width (iPad) keeps the list in a readable column
  /// and stands the schedule beside it, so nothing needs opening. A phone on
  /// its side (a compact height) has room for little above the first task, so
  /// it stands the brief, the date, briefing, and day strip, beside the task
  /// list, each scrolling on its own; the strip still opens the schedule sheet.
  @ViewBuilder
  private var content: some View {
    if horizontalSizeClass == .regular {
      HStack(spacing: 0) {
        todayList(openSchedule: nil)
          .mobileReadableWidth(680)
        Divider()
          .ignoresSafeArea()
        MobileTodayScheduleList(
          store: store,
          openTask: { task in store.routePath.append(.task(task.id)) },
          openEvent: { event in
            store.prepareCalendarDraft(for: event)
            editingCalendarEvent = event
          }
        )
        .frame(width: 380)
        .background(alignment: .top) { skyWash }
        .accessibilityIdentifier("today.schedulePane")
      }
      .modifier(chrome)
    } else if verticalSizeClass == .compact {
      HStack(spacing: 0) {
        todayList(.brief, openSchedule: { isShowingSchedule = true })
          .frame(maxWidth: 360)
        Divider()
          .ignoresSafeArea()
        todayList(.tasks, openSchedule: nil)
      }
      .modifier(chrome)
    } else {
      todayList(openSchedule: { isShowingSchedule = true })
        .modifier(chrome)
    }
  }

  private var chrome: MobileTodayPageChrome {
    MobileTodayPageChrome(
      store: store, editingHabit: $editingHabit, editingCalendarEvent: $editingCalendarEvent,
      isShowingSchedule: $isShowingSchedule)
  }

  private func todayList(
    _ portion: MobileTodayPage.Portion = .whole, openSchedule: (() -> Void)?
  ) -> some View {
    // Per-minute, so a running time and the strip's now line follow the clock
    // without a reload.
    TimelineView(.everyMinute) { _ in
      MobileTodayPage(
        store: store,
        page: store.calmToday,
        portion: portion,
        nowMinutes: store.nowMinutesInProductDay,
        editHabit: { habit in
          store.prepareHabitDraft(for: habit)
          editingHabit = habit
        },
        openSchedule: openSchedule)
    }
    .scrollContentBackground(.hidden)
    .background(alignment: .top) { skyWash }
    .background(LorvexDesign.Palette.groupedBackground)
  }

  /// The time-of-day tint behind a Today pane. It runs under the bar and, on a
  /// phone on its side, beside the cutout and the home indicator too, so the
  /// wash reaches every edge the page does. On iPad the list and the
  /// schedule pane each draw it over the same height, so the tint reads as
  /// one wash across the split instead of ending at the divider.
  @ViewBuilder
  private var skyWash: some View {
    if let nowMinutes = store.nowMinutesInProductDay {
      LorvexSkyWash(nowMinutes: nowMinutes)
        .ignoresSafeArea(edges: [.top, .horizontal])
    }
  }

  #if DEBUG
    /// The screenshot run's `-lorvexUIPreviewSuggestedTimes` hook: once Today
    /// has loaded and the launch seed has finished, suggest times, and on
    /// iPhone open the schedule sheet they wait in; iPad shows them in the
    /// standing pane. A suggestion plans around the calendar as it stands, so
    /// asking before the seed has written its events would leave them out.
    private func suggestTimesForPreviewIfRequested() async {
      guard CommandLine.arguments.contains("-lorvexUIPreviewSuggestedTimes") else { return }
      await MobileSeedDebugState.waitUntilFinished()
      try? await Task.sleep(for: .seconds(0.5))
      await store.suggestDayTimes()
      if horizontalSizeClass != .regular { isShowingSchedule = true }
    }
  #endif
}

/// Today's page-level chrome shared by the iPhone and iPad layouts: loading the
/// workday and done count, pull to refresh, the Settings button, and the habit,
/// schedule, and event sheets.
private struct MobileTodayPageChrome: ViewModifier {
  @Bindable var store: MobileStore
  @Binding var editingHabit: LorvexHabit?
  @Binding var editingCalendarEvent: CalendarTimelineEvent?
  @Binding var isShowingSchedule: Bool

  func body(content: Content) -> some View {
    content
      .task {
        await store.loadWorkdayWindow()
        await store.loadDoneTodayCount()
      }
      .onChange(of: store.snapshot.today) { _, _ in
        Task { await store.loadDoneTodayCount() }
      }
      .refreshable { await store.refresh() }
      .toolbar {
        // Capture is the tab bar's round + on every tab, so the bar here holds
        // only Settings: a typed route on the Today stack, so keyboard mnemonics
        // and debug deep links push the same screen.
        NavigationLink(value: MobileRoute.workspace(.settings)) {
          Label(
            String(
              localized: "today.toolbar.settings", defaultValue: "Settings", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "gearshape")
        }
        .lorvexToolbarHoverEffect()
        .accessibilityIdentifier("today.toolbar.settings")
      }
      .sheet(item: $editingHabit) { habit in
        MobileStoreEditHabitSheet(
          habit: habit,
          store: store,
          isPresented: Binding(
            get: { editingHabit != nil },
            set: { if !$0 { editingHabit = nil } }
          )
        )
      }
      .sheet(isPresented: $isShowingSchedule) {
        MobileTodayScheduleSheet(
          store: store,
          openTask: { task in store.routePath.append(.task(task.id)) },
          openEvent: { event in
            store.prepareCalendarDraft(for: event)
            editingCalendarEvent = event
          })
      }
      .sheet(item: $editingCalendarEvent) { event in
        MobileStoreEditCalendarEventSheet(
          event: event,
          store: store,
          isPresented: Binding(
            get: { editingCalendarEvent != nil },
            set: { if !$0 { editingCalendarEvent = nil } }
          )
        )
      }
  }
}
