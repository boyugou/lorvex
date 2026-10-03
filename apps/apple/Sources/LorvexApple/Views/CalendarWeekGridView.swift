import LorvexCore
import SwiftUI

/// Native week timeline view: a left hour gutter
/// (absolute time axis), seven day columns, events positioned as blocks by
/// start time + duration with overlap-lane packing, an all-day strip on top,
/// and a live "now" indicator on today's column.
///
/// The visible week (`weekStart`) drives the data fetch through the caller, so
/// only the visible range is loaded. Tapping a block opens edit; tapping an
/// empty slot prefills create-at-that-time.
struct CalendarWeekGridView: View {
  @Bindable var store: AppStore
  let weekStart: Date
  var visibleDayCount: Int = 7
  let selectEvent: (CalendarTimelineEvent) -> Void
  /// Right-click "Edit" on an editable event block. Defaults to a no-op for
  /// callers (e.g. previews) that don't wire the context menu.
  var editEvent: (CalendarTimelineEvent) -> Void = { _ in }
  /// Right-click "Delete" on an editable event block (raises the workspace's
  /// confirmation / occurrence-scope dialog).
  var requestDeleteEvent: (CalendarTimelineEvent) -> Void = { _ in }
  let openTask: (LorvexTask) -> Void
  /// Opens the create-event sheet pre-filled with a start instant + duration.
  /// Duration is in minutes; tap-to-create passes a default (60), drag-to-
  /// create on the empty slot passes the dragged duration (snapped to 15-min).
  let createAt: (Date, Int, Int) -> Void

  let hourHeight: CGFloat = CalendarWeekGridMetrics.hourHeight
  /// Wide enough for the display locale's widest hour label on one line.
  var gutterWidth: CGFloat { CalendarWeekGridMetrics.gutterWidth(fitting: (0..<24).map(hourLabel)) }
  /// Maximum simultaneous lanes shown per day column before the "+N more" overflow badge appears.
  let maxDisplayedLanes = 3
  // Read the calendar from the environment so a timezone / first-weekday change
  // (including a mid-session DST shift) flows into the now-line and day
  // boundaries rather than freezing whatever `Calendar.current` was at init.
  @Environment(\.calendar) var calendar
  @Environment(\.undoManager) var undoManager
  /// Drag-to-move and drag-to-resize snap to this granularity (matching the
  /// 15-minute increments most calendar UIs use).
  static let snapMinutes: Int = 15
  /// Minimum drag distance before a move gesture is recognised, so a tap
  /// still selects the event instead of starting a drag.
  static let dragMinimumDistance: CGFloat = 6
  /// Minimum block duration the resize handle can produce. Tied to the layout's
  /// render clamp so a resized block can't end up shorter than the height the
  /// grid will actually draw it at (which would desync the end-edge handle).
  static let minimumBlockMinutes = CalendarGridModel.minBlockMinutes

  @State var rescheduleDraft: RescheduleDraft? = nil
  @State var createDraft: CreateDraft? = nil
  /// Day column currently hovered by a dragged task pill (all-day strip),
  /// driving the drop-target highlight.
  @State var dropTargetedDay: Date? = nil
  /// Event under the pointer. Resize grips are drawn only for it and for the
  /// selected block, so a dense week grid is not peppered with permanent marks
  /// that read as stray rules rather than affordances. The grips' transparent
  /// hit area stays live either way, so the resize cursor and the drag arm the
  /// moment the pointer reaches a block edge.
  @State var hoveredEventID: String? = nil
  @State private var overflowPopoverDayID: CalendarGridDay.ID? = nil
  /// Day column whose all-day "+N more" popover is open. Internal (not private)
  /// so the all-day strip in `CalendarWeekGridChrome` can drive it.
  @State var allDayOverflowDayID: CalendarGridDay.ID? = nil

  struct RescheduleDraft: Equatable {
    let eventID: String
    let kind: Kind
    var translation: CGSize
    var columnWidth: CGFloat
    enum Kind { case move, resize, resizeTop }
  }

  /// Drag-to-create preview state: which day column the user pressed on, and
  /// the start + current Y inside that column (in points). The view renders
  /// a translucent ghost block from `startY` to `currentY`. Snapped to
  /// 15-minute increments on commit.
  struct CreateDraft: Equatable {
    let dayIndex: Int
    var startY: CGFloat
    var currentY: CGFloat
    /// Returns the (min, max) Y in points so the preview rect renders
    /// upward-dragging selections correctly.
    var ordered: (top: CGFloat, bottom: CGFloat) {
      (min(startY, currentY), max(startY, currentY))
    }
  }

  private var days: [CalendarGridDay] {
    CalendarGridModel.buildDays(
      rangeStart: weekStart,
      dayCount: visibleDayCount,
      calendar: calendar,
      events: store.calendarTimeline?.events ?? [],
      tasks: store.scheduledTasks,
      dayKeyFor: { AppStore.ymdFormatter.string(from: $0) }
    )
  }

  private var totalHeight: CGFloat { hourHeight * 24 }

  var body: some View {
    let columns = days
    let now = LorvexPreviewClock.now(in: calendar)
    let todayKey = AppStore.ymdFormatter.string(from: now)
    let nowMinute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
    let anchorHour = CalendarGridModel.initialScrollAnchorHour(
      for: columns, todayKey: todayKey, nowMinute: nowMinute)
    // Re-scroll fires only on week / event-content change, never when the wall
    // clock crosses an hour or an unrelated store update re-evaluates `body`.
    // The signature therefore keys off the CONTENT-only anchor; the now-aware
    // `anchorHour` still drives the actual scroll target (initial appear + week
    // navigation), so a live clock tick can't yank the user away from a
    // position they scrolled to (the mobile day view guards this with
    // `userHasScrolledTimeAxis`; the week grid has no such state).
    let scrollSignature = calendarWeekScrollAnchorSignature(
      columns: columns,
      anchorHour: CalendarGridModel.initialScrollAnchorHour(for: columns),
      weekStart: weekStart)
    VStack(spacing: 0) {
      header(columns)
      Divider()
      allDayStrip(columns)
      Divider()
      ScrollViewReader { proxy in
        ScrollView {
          HStack(alignment: .top, spacing: 0) {
            hourGutter()
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, day in
              dayColumn(day, dayIndex: index, totalDays: columns.count)
                // Draw the column separator as a trailing overlay rather than an
                // interleaved `Divider()`: a layout-consuming divider made each
                // grid column ~1pt narrower than the matching header / all-day
                // column, so event blocks and the now-line drifted left of their
                // day number. A zero-width overlay keeps all three rows on
                // identical `maxWidth: .infinity` columns.
                .overlay(alignment: .trailing) {
                  Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                }
            }
          }
          .frame(height: totalHeight)
        }
        // No scroller on the time axis. While one is shown the scroll view
        // narrows its content, so the seven day columns shrink under a header
        // and all-day strip that are laid out above the scroll view at full
        // width: every day number drifts right of the column it names, by the
        // scroller's width at the last day, and an all-day pill overhangs into
        // the next day. Suppressing it keeps one column geometry at all times,
        // and the grid loses nothing — the hour gutter already says where the
        // view sits in the day, which is all a scroller would report.
        .scrollIndicators(.never)
        .onAppear {
          proxy.scrollTo(WeekGridScrollAnchor.hour(anchorHour), anchor: .top)
        }
        .onChange(of: scrollSignature) { _, _ in
          lorvexAnimated(.snappy(duration: 0.18)) {
            proxy.scrollTo(WeekGridScrollAnchor.hour(anchorHour), anchor: .top)
          }
        }
        .onChange(of: weekStart) { _, _ in
          // The grid identity is reused across week navigation, so an interrupted
          // drag (resign-key, mid-drag refresh) would otherwise strand its
          // translucent draft rectangle on the new week. Clear both drafts.
          createDraft = nil
          rescheduleDraft = nil
          dropTargetedDay = nil
        }
        .onDisappear {
          createDraft = nil
          rescheduleDraft = nil
          dropTargetedDay = nil
        }
      }
      .overlay(alignment: .top) {
        // An empty range stays a bare grid: the empty hours already say nothing
        // is scheduled, and the toolbar's add button creates an event. Only a
        // blocked-access grid gets a banner, since there the emptiness means
        // "Calendar access is off," not "nothing scheduled."
        if isEmptyWeek(columns), EventKitAuthorizationHelper().needsSettingsRecovery {
          CalendarWeekAuthorizeOverlay()
            .padding(.top, LorvexDesign.Spacing.l)
            .padding(.leading, gutterWidth)
            .padding(.horizontal, LorvexDesign.Spacing.l)
        }
      }
    }
  }

  private func isEmptyWeek(_ columns: [CalendarGridDay]) -> Bool {
    columns.allSatisfy(\.isEmpty)
  }

  // MARK: Day column

  private func dayColumn(
    _ day: CalendarGridDay, dayIndex: Int, totalDays: Int
  ) -> some View {
    GeometryReader { geo in
      let width = geo.size.width
      ZStack(alignment: .topLeading) {
        // Hour grid lines.
        VStack(spacing: 0) {
          ForEach(0..<24, id: \.self) { _ in
            CalendarWeekGridHourCell(hourHeight: hourHeight)
          }
        }

        // The now line sits under the blocks (their zIndex lifts them above
        // it), which are opaque, so it runs through the free time and never
        // across a block's title. Scope the per-minute tick to just the
        // now-guide so the rest of the grid (event blocks, grid lines,
        // interaction overlays) is not rebuilt every 60 seconds. Today gets the
        // red live now-line; adjacent days get a faint guide at the same
        // time-of-day for cross-column reading.
        TimelineView(.periodic(from: .now, by: 60)) { context in
          nowLine(now: LorvexPreviewClock.now(in: calendar, tick: context.date), isToday: isToday(day.date))
        }
        .allowsHitTesting(false)

        // Empty-slot interaction overlay sits BEHIND the event blocks in
        // z-order so blocks catch their own taps / drags first; empty-area
        // hits fall through to this layer. Tap → create-at-hour with default
        // 60-min duration; drag → create-with-custom-duration. Drag has
        // `minimumDistance: 6` so taps still fire the simple-create handler.
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture { location in
            let minutes = minuteOfDay(forY: location.y)
            let hourSnapped = (minutes / 60) * 60
            createAt(day.date, hourSnapped, 60)
          }
          .gesture(createGesture(for: day, dayIndex: dayIndex))

        // Drag-to-create preview block (only visible while dragging in this
        // column). Non-hit-testable so it never blocks gestures. Shows the
        // snapped start–end window in a small overlay so the user sees what
        // they'll get before they release.
        if let draft = createDraft, draft.dayIndex == dayIndex {
          let bounds = draft.ordered
          let startMin = snappedMinute(forY: bounds.top, snapTo: Self.snapMinutes)
          let endMin = snappedMinute(forY: bounds.bottom, snapTo: Self.snapMinutes, roundingUp: true)
          let span = max(endMin - startMin, Self.minimumBlockMinutes)
          ZStack(alignment: .topLeading) {
            Rectangle()
              .fill(.tint.opacity(0.18))
              .overlay(
                RoundedRectangle(cornerRadius: CalendarWeekGridMetrics.eventCornerRadius)
                  .strokeBorder(.tint.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
              )
            if max(bounds.bottom - bounds.top, 4) > 18 {
              Text(lorvexClockRangeLabel(startMinutes: startMin, endMinutes: startMin + span))
              .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
              .foregroundStyle(.tint)
              .padding(.horizontal, 4)
              .padding(.vertical, 1)
            }
          }
          .frame(height: max(bounds.bottom - bounds.top, 4))
          .offset(y: bounds.top)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        }

        ForEach(day.timedBlocks.filter { $0.lane < maxDisplayedLanes }) { block in
          eventBlock(
            block,
            dayIndex: dayIndex,
            totalDays: totalDays,
            columnWidth: width)
        }

        ForEach(day.taskBlocks.filter { $0.lane < maxDisplayedLanes }) { block in
          taskBlock(block, on: day, columnWidth: width)
        }

        overflowBadge(for: day)

        if isToday(day.date) {
          // Today's dot draws above every block, which rise to zIndex 2 while
          // selected or dragged, so one that spans the current time never
          // covers it; the line itself runs under them.
          TimelineView(.periodic(from: .now, by: 60)) { context in
            nowDot(now: LorvexPreviewClock.now(in: calendar, tick: context.date))
          }
          .allowsHitTesting(false)
          .zIndex(3)
        }
      }
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private func overflowBadge(for day: CalendarGridDay) -> some View {
    let hidden = day.timedBlocks.filter { $0.lane >= maxDisplayedLanes }
    let hiddenTasks = day.taskBlocks.filter { $0.lane >= maxDisplayedLanes }
    if !hidden.isEmpty || !hiddenTasks.isEmpty {
      let earliestStart = (hidden.map(\.startMin) + hiddenTasks.map(\.startMin)).min() ?? 0
      let badgeY = CGFloat(earliestStart) / 60.0 * hourHeight
      Button {
        overflowPopoverDayID = day.id
      } label: {
        Text("+\(hidden.count + hiddenTasks.count)")
          .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, LorvexDesign.Spacing.xs)
          .padding(.vertical, LorvexDesign.Spacing.xxs)
          .background(Capsule().fill(Color.secondary.opacity(0.75)))
      }
      .buttonStyle(.borderless)
      .frame(maxWidth: .infinity, alignment: .trailing)
      .padding(.trailing, LorvexDesign.Spacing.xxs)
      .offset(y: badgeY)
      .accessibilityLabel(
        String(
          localized: "calendar.overflow.more_events.a11y",
          defaultValue: "\(hidden.count + hiddenTasks.count) more events",
          table: "Localizable", bundle: LorvexL10n.bundle))
      .popover(
        isPresented: Binding(
          get: { overflowPopoverDayID == day.id },
          set: { if !$0 { overflowPopoverDayID = nil } }
        )
      ) {
        overflowPopover(blocks: hidden, taskBlocks: hiddenTasks)
      }
    }
  }

  private func overflowPopover(
    blocks: [CalendarGridTimedBlock], taskBlocks: [CalendarGridTaskBlock]
  ) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      Text(LocalizedStringResource("calendar.overflow.title", defaultValue: "Hidden events", table: "Localizable", bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.primaryEmphasis)
      ForEach(taskBlocks.sorted { $0.startMin < $1.startMin }) { block in
        Button {
          overflowPopoverDayID = nil
          openTask(block.task)
        } label: {
          HStack(spacing: LorvexDesign.Spacing.s) {
            Circle()
              .fill(LorvexDesign.Palette.accent)
              .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
              Text(userContent: block.task.title)
                .font(LorvexDesign.Typography.secondaryText)
                .lineLimit(1)
              Text(lorvexClockRangeLabel(startMinutes: block.startMin, endMinutes: block.endMin))
                .font(LorvexDesign.Typography.tertiaryText)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: LorvexDesign.Spacing.s)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(taskBlockAccessibilityLabel(block))
      }
      ForEach(blocks.sorted { $0.startMin < $1.startMin }) { block in
        Button {
          overflowPopoverDayID = nil
          selectEvent(block.event)
        } label: {
          HStack(spacing: LorvexDesign.Spacing.s) {
            Circle()
              .fill(eventColor(block.event))
              .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
              Text(userContent: block.event.title)
                .font(LorvexDesign.Typography.secondaryText)
                .lineLimit(1)
              // The block's own time: its range, or for one day of an event
              // that runs past midnight its start or "Until 1:30 AM".
              Text(block.rangeLabel ?? block.timeLabel ?? "")
                .font(LorvexDesign.Typography.tertiaryText)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: LorvexDesign.Spacing.s)
            if block.event.editable {
              Image(systemName: "pencil")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!block.event.editable)
        .accessibilityLabel(calendarEventAccessibilityLabel(block.event))
      }
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(width: 260, alignment: .leading)
  }

}
