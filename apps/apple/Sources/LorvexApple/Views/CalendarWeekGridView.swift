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
  let gutterWidth: CGFloat = CalendarWeekGridMetrics.gutterWidth
  /// Maximum simultaneous lanes shown per day column before the "+N more" overflow badge appears.
  let maxDisplayedLanes = 3
  // Read the calendar from the environment so a timezone / first-weekday change
  // (including a mid-session DST shift) flows into the now-line and day
  // boundaries rather than freezing whatever `Calendar.current` was at init.
  @Environment(\.calendar) var calendar
  /// Drag-to-move and drag-to-resize snap to this granularity (matching the
  /// 15-minute increments most calendar UIs use).
  static let snapMinutes: Int = 15
  /// Minimum drag distance before a move gesture is recognised, so taps still
  /// fire the edit-sheet handler without being eaten.
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
      events: store.filteredCalendarEvents,
      tasks: store.filteredScheduledTasks,
      dayKeyFor: { AppStore.ymdFormatter.string(from: $0) }
    )
  }

  private var totalHeight: CGFloat { hourHeight * 24 }

  var body: some View {
    let columns = days
    let now = Date()
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
        if isEmptyWeek(columns) {
          Group {
            // A blocked-access empty grid means "Calendar access is off," not
            // "nothing scheduled" — say so for the recoverable states.
            if EventKitAuthorizationHelper().needsSettingsRecovery {
              CalendarWeekAuthorizeOverlay()
            } else {
              CalendarWeekEmptyOverlay(visibleDayCount: visibleDayCount) {
                let target = emptyWeekCreateTarget(columns)
                createAt(target.date, target.minutes, 60)
              }
            }
          }
          .padding(.top, LorvexDesign.Spacing.l)
          .padding(.leading, gutterWidth)
          .padding(.horizontal, LorvexDesign.Spacing.l)
        }
      }
    }
  }

  private func isEmptyWeek(_ columns: [CalendarGridDay]) -> Bool {
    columns.allSatisfy {
      $0.allDayEvents.isEmpty && $0.scheduledTasks.isEmpty && $0.timedBlocks.isEmpty
    }
  }

  private func emptyWeekCreateTarget(_ columns: [CalendarGridDay]) -> (date: Date, minutes: Int) {
    let now = Date()
    if let today = columns.first(where: { calendar.isDate($0.date, inSameDayAs: now) }) {
      let nextUsefulHour = min(max(calendar.component(.hour, from: now) + 1, 9), 17)
      return (today.date, nextUsefulHour * 60)
    }
    return (columns.first?.date ?? weekStart, 9 * 60)
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
              Text(
                "\(Self.hmLabel(minuteOfDay: startMin))–\(Self.hmLabel(minuteOfDay: startMin + span))"
              )
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

        overflowBadge(for: day)

        // Scope the per-minute tick to just the now-guide so the rest of the
        // grid (event blocks, grid lines, interaction overlays) is not rebuilt
        // every 60 seconds. Today gets the red live now-line; adjacent days get
        // a faint guide at the same time-of-day for cross-column reading.
        TimelineView(.periodic(from: .now, by: 60)) { context in
          nowLine(now: context.date, isToday: isToday(day.date))
        }
      }
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private func overflowBadge(for day: CalendarGridDay) -> some View {
    let hidden = day.timedBlocks.filter { $0.lane >= maxDisplayedLanes }
    if !hidden.isEmpty,
      let earliest = hidden.min(by: { $0.startMin < $1.startMin })
    {
      let badgeY = CGFloat(earliest.startMin) / 60.0 * hourHeight
      Button {
        overflowPopoverDayID = day.id
      } label: {
        Text("+\(hidden.count)")
          .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 5)
          .padding(.vertical, 2)
          .background(Capsule().fill(Color.secondary.opacity(0.75)))
      }
      .buttonStyle(.borderless)
      .frame(maxWidth: .infinity, alignment: .trailing)
      .padding(.trailing, 2)
      .offset(y: badgeY)
      .accessibilityLabel(
        String(
          format: String(
            localized: "calendar.overflow.more_events.a11y",
            defaultValue: "%lld more events",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          hidden.count))
      .popover(
        isPresented: Binding(
          get: { overflowPopoverDayID == day.id },
          set: { if !$0 { overflowPopoverDayID = nil } }
        )
      ) {
        overflowPopover(blocks: hidden)
      }
    }
  }

  private func overflowPopover(blocks: [CalendarGridTimedBlock]) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      Text(LocalizedStringResource("calendar.overflow.title", defaultValue: "Hidden events", table: "Localizable", bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.primaryEmphasis)
      ForEach(blocks.sorted { $0.startMin < $1.startMin }) { block in
        Button {
          overflowPopoverDayID = nil
          selectEvent(block.event)
        } label: {
          HStack(spacing: LorvexDesign.Spacing.s) {
            Circle()
              .fill(eventColor(block.event))
              .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
              Text(block.event.title)
                .font(LorvexDesign.Typography.secondaryText)
                .lineLimit(1)
              Text(calendarWeekOverflowTimeText(for: block.event))
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
        .accessibilityLabel(calendarWeekOverflowBlockAccessibilityLabel(block))
      }
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(width: 260, alignment: .leading)
  }

}
