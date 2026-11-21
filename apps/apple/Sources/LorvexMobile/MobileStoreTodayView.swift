import LorvexCore
import SwiftUI

enum MobileTodayLayout {
  case single, scheduleBesideTasks, briefBesideTasks

  static let scheduleWidth: CGFloat = 380

  // Leave room for an inset task row, its completion control and its metadata.
  static func minimumTaskWidth(for typeSize: DynamicTypeSize) -> CGFloat {
    typeSize >= .xxLarge ? 520 : 440
  }

  static func resolve(
    width: CGFloat, regularWidth: Bool, compactHeight: Bool, typeSize: DynamicTypeSize
  ) -> Self {
    guard !typeSize.isAccessibilitySize else { return .single }
    let minimumTaskWidth = minimumTaskWidth(for: typeSize)
    if regularWidth, width >= minimumTaskWidth + scheduleWidth + 1 { return .scheduleBesideTasks }
    if compactHeight, width >= minimumTaskWidth + 280 + 1 { return .briefBesideTasks }
    return .single
  }
}

struct MobileStoreTodayView: View {
  @Bindable var store: MobileStore
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var editingHabit: LorvexHabit?
  @State private var editingCalendarEvent: CalendarTimelineEvent?
  @State private var isShowingSchedule = false
  @State private var showsTaskPicker = false

  var body: some View {
    GeometryReader { geometry in
      let layout = MobileTodayLayout.resolve(
        width: geometry.size.width, regularWidth: horizontalSizeClass == .regular,
        compactHeight: verticalSizeClass == .compact, typeSize: typeSize)
      content(layout, width: geometry.size.width)
        #if DEBUG
          .task { await suggestTimesForPreviewIfRequested(layout: layout) }
        #endif
    }
    .modifier(chrome)
    .sheet(isPresented: $showsTaskPicker) {
      MobileTodayTaskPicker(store: store, day: store.logicalTodayString)
    }
    .environment(\.lorvexTaskRowDay, store.logicalTodayString)
    #if DEBUG
      .onAppear {
        // Dev/QA only: the `lorvex://sheet/eventdetail` screenshot hook opens
        // the detail of a staged mirrored event without a tap.
        if let event = MobileCalendarDebugState.takePendingDetailEvent() {
          editingCalendarEvent = event
        }
      }
      .onChange(of: MobileCalendarDebugState.pendingDetailEvent) { _, event in
        // TabView may keep Today mounted before a later screenshot URL stages
        // its event, so appearance alone cannot deliver every request.
        if event != nil, let event = MobileCalendarDebugState.takePendingDetailEvent() {
          editingCalendarEvent = event
        }
      }
    #endif
  }

  private func content(_ layout: MobileTodayLayout, width: CGFloat) -> some View {
    HStack(spacing: 0) {
      if layout == .briefBesideTasks {
        todayList(.brief, openSchedule: { isShowingSchedule = true })
          .frame(width: min(360, width - MobileTodayLayout.minimumTaskWidth(for: typeSize) - 1))
        Divider().ignoresSafeArea()
      }

      // Keep the list that owns the first-task draft mounted across resizes.
      todayList(
        layout == .briefBesideTasks ? .tasks : .whole,
        openSchedule: layout == .single ? { isShowingSchedule = true } : nil
      )
      .mobileReadableWidth(680)

      if layout == .scheduleBesideTasks {
        Divider().ignoresSafeArea()
        MobileTodayScheduleList(
          store: store,
          openTask: { task in store.routePath.append(.task(task.id)) },
          openEvent: openEvent
        )
        .frame(width: MobileTodayLayout.scheduleWidth)
        .background(alignment: .top) { skyWash }
        .accessibilityIdentifier("today.schedulePane")
      }
    }
  }

  private func openEvent(_ event: CalendarTimelineEvent) {
    store.prepareCalendarDraft(for: event)
    editingCalendarEvent = event
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
    TimelineView(.everyMinute) { context in
      let tick = context.date
      let schedule = store.todaySchedule(at: tick)
      let minutes = store.todayMinutes(at: tick)
      let page = store.calmToday(at: tick)
      MobileTodayPage(
        store: store,
        page: page,
        workCue: store.todayWorkCue(for: page, at: tick),
        portion: portion,
        nowMinutes: minutes,
        editHabit: { habit in
          store.prepareHabitDraft(for: habit)
          editingHabit = habit
        },
        openSchedule: openSchedule,
        chooseTask: { showsTaskPicker = true },
        stripSegments: store.todayStripSegments(in: schedule, now: minutes),
        appointment: MobileTodayAppointment.firstGlance(in: schedule),
        openEvent: openEvent)
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
    /// layouts without a standing schedule, open the sheet they wait in.
    /// Suggest after seeding so the proposal includes the seeded calendar events.
    private func suggestTimesForPreviewIfRequested(layout: MobileTodayLayout) async {
      guard CommandLine.arguments.contains("-lorvexUIPreviewSuggestedTimes") else { return }
      await MobileSeedDebugState.waitUntilFinished()
      try? await Task.sleep(for: .seconds(0.5))
      await store.suggestDayTimes()
      if layout != .scheduleBesideTasks { isShowingSchedule = true }
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
        MobileStoreCalendarEventSheet(
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
