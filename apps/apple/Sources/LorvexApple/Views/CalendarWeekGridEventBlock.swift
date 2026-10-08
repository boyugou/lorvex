import LorvexCore
import SwiftUI

enum CalendarEventBlockMetrics {
  static let verticalPadding: CGFloat = 2
  static let horizontalPadding: CGFloat = 4
  static let compactTrailingPadding: CGFloat = 1
  static let laneGap: CGFloat = 2
  static let cornerRadius: CGFloat = CalendarWeekGridMetrics.eventCornerRadius
  static let accentRailWidth: CGFloat = 2.5
  static let activeShadowRadius: CGFloat = 7
  static let selectedShadowRadius: CGFloat = 5
  static let resizeHandleHitHeight: CGFloat = 8
  static let resizeHandleWidth: CGFloat = 18
  /// How far from the leading edge a task block's completion circle reaches:
  /// its own padding, the circle, and a little slack.
  static let taskCircleInset: CGFloat = 24
}

extension CalendarWeekGridView {
  func eventBlock(
    _ block: CalendarGridTimedBlock,
    on day: CalendarGridDay,
    dayIndex: Int,
    totalDays: Int,
    columnWidth: CGFloat
  ) -> some View {
    // Cap the divisor at the number of lanes actually drawn: when a cluster
    // overflows `maxDisplayedLanes`, the hidden lanes are collapsed into the
    // "+N more" badge, so the visible blocks fill the column instead of leaving
    // dead lanes sized for events that aren't shown.
    let laneWidth = columnWidth / CGFloat(min(block.laneCount, maxDisplayedLanes))
    let baseY = CGFloat(block.startMin) / 60 * hourHeight
    // The model's drawn end already holds a short block open to
    // `CalendarGridModel.minBlockMinutes` when nothing starts within that
    // window; when something does, the block gets its real span, so a floor
    // here would only run it under the next block.
    let baseHeight = CGFloat(block.drawnEndMin - block.startMin) / 60 * hourHeight
    let color = eventColor(block.event)
    let active = rescheduleDraft?.blockID == block.event.id ? rescheduleDraft : nil
    // The block whose inspector is open reads as selected: a stronger fill, a
    // full-color ring, and a soft lift. This gives the open inspector a visual
    // anchor and makes the tap-again-to-close toggle discoverable.
    let isSelected = store.selectedCalendarEventID == block.event.id
    let preview = CalendarBlockMovePreview(draft: active)
    // A resize in progress cannot shrink the block below a quarter hour.
    let renderedHeight =
      active == nil
      ? baseHeight
      : max(baseHeight + preview.resizeBottom - preview.resizeTop, hourHeight / 4)
    let isEditable =
      block.event.editable && !block.event.allDay && !block.event.supportsScopedMutation
      && !block.event.isMultiDay
    let showsResizeGrips = isSelected || hoveredBlockID == block.event.id
    // Overlap can leave a lane too narrow for a time line or a word: it then
    // shows the title alone, and the tooltip carries the rest.
    let isCompact = laneWidth < LorvexDesign.CalendarMetrics.compactLaneWidth
    let isTight = baseHeight < LorvexDesign.CalendarMetrics.tightBlockHeight
    let label = blockAccessibilityLabel(
      calendarEventAccessibilityLabel(block.event), on: day, totalDays: totalDays)
    // While a drag is under way the block reads the time its release would give
    // it.
    let landed = active?.landedTime(
      of: block.startMin..<block.endMin, hourHeight: hourHeight,
      minimumLength: Self.minimumBlockMinutes)

    return Group {
      if isCompact {
        LorvexCalendarCompactBlockTitle(block.event.title)
          .padding(.vertical, isTight ? 0 : CalendarEventBlockMetrics.verticalPadding)
      } else {
        LorvexCalendarBlockText(
          title: block.event.title,
          time: landed.map { lorvexClockTimeLabel(minutes: $0.lowerBound) } ?? block.timeLabel,
          range: landed.map {
            lorvexClockRangeLabel(startMinutes: $0.lowerBound, endMinutes: $0.upperBound)
          } ?? block.rangeLabel,
          verticalPadding: CalendarEventBlockMetrics.verticalPadding
        )
      }
    }
    .padding(.leading, CalendarEventBlockMetrics.horizontalPadding)
    .padding(
      .trailing,
      isCompact ? CalendarEventBlockMetrics.compactTrailingPadding : CalendarEventBlockMetrics.horizontalPadding
    )
    .frame(
      width: max(laneWidth - CalendarEventBlockMetrics.laneGap, 8),
      height: renderedHeight,
      alignment: .topLeading
    )
    .clipped()
    .lorvexOpaqueTintBackground(
      color.opacity(active != nil || isSelected ? 0.24 : 0.16),
      in: RoundedRectangle(cornerRadius: CalendarEventBlockMetrics.cornerRadius)
    )
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(color)
        .frame(width: CalendarEventBlockMetrics.accentRailWidth)
        .clipShape(RoundedRectangle(cornerRadius: CalendarEventBlockMetrics.accentRailWidth / 2))
    }
    .overlay {
      RoundedRectangle(cornerRadius: CalendarEventBlockMetrics.cornerRadius)
        .stroke(
          isSelected
            ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(active == nil ? 0.28 : 0.55)),
          lineWidth: isSelected ? 1.5 : (active == nil ? 0.5 : 1))
    }
    // The block is tap-to-open, so it takes the pointing-hand cursor. Applied
    // beneath the resize-handle overlays below so their resize cursor still wins
    // in the handle bands (the topmost cursor rect under the pointer wins).
    .calendarPointingHandCursor()
    .onHover { inside in
      if inside {
        hoveredBlockID = block.event.id
      } else if hoveredBlockID == block.event.id {
        hoveredBlockID = nil
      }
    }
    .overlay(alignment: .topTrailing) {
      if block.event.editable && !isEditable && !isCompact {
        inGridEditSheetHint(for: block)
      }
    }
    .overlay(alignment: .top) {
      if isEditable && baseHeight > 24 {
        resizeHandle(
          alignment: .top,
          color: color,
          visible: showsResizeGrips,
          gesture: resizeTopGesture(for: block),
          select: { selectEvent(block.event) })
      }
    }
    .overlay(alignment: .bottom) {
      if isEditable {
        resizeHandle(
          alignment: .bottom,
          color: color,
          visible: showsResizeGrips,
          gesture: resizeGesture(for: block),
          select: { selectEvent(block.event) })
      }
    }
    .contentShape(Rectangle())
    .zIndex(active != nil || isSelected ? 2 : 1)
    .offset(
      x: CGFloat(block.lane) * laneWidth + preview.move.width,
      y: baseY + preview.move.height + preview.resizeTop
    )
    .opacity(active == nil ? 1 : 0.85)
    .shadow(
      color: active != nil ? .black.opacity(0.16) : (isSelected ? color.opacity(0.35) : .clear),
      radius: active != nil
        ? CalendarEventBlockMetrics.activeShadowRadius
        : (isSelected ? CalendarEventBlockMetrics.selectedShadowRadius : 0),
      y: 2
    )
    .gesture(
      isEditable
        ? moveGesture(
          for: block,
          dayIndex: dayIndex,
          totalDays: totalDays,
          columnWidth: columnWidth)
        : nil
    )
    .onTapGesture { selectEvent(block.event) }
    .focusable(true)
    .onKeyPress(.return) {
      selectEvent(block.event)
      return .handled
    }
    .onKeyPress(.space) {
      selectEvent(block.event)
      return .handled
    }
    .help(isCompact ? label : "")
    // One stop per block: its title and time lines would each read the label.
    // A tap gesture has no press action of its own, so the block offers one.
    .accessibilityElement(children: .ignore)
    .accessibilityAddTraits(.isButton)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityLabel(label)
    .accessibilityAction { selectEvent(block.event) }
    .accessibilitySortPriority(
      Self.accessibilitySortPriority(
        dayIndex: dayIndex, totalDays: totalDays, startMinutes: block.startMin))
    .contextMenu {
      CalendarEventContextMenu(
        event: block.event, select: selectEvent, edit: editEvent,
        requestDelete: requestDeleteEvent)
    }
  }

  private func inGridEditSheetHint(for block: CalendarGridTimedBlock) -> some View {
    Image(
      systemName: block.event.isRecurring || block.event.supportsScopedMutation
        ? "repeat.circle.fill" : "pencil.circle.fill"
    )
    .font(LorvexDesign.Typography.tertiaryText)
    .foregroundStyle(.secondary)
    .padding(LorvexDesign.Spacing.xxs)
    .background(.background.opacity(0.82), in: Circle())
    .help(
      String(
        localized: "calendar.weekgrid.edit_hint.help",
        defaultValue: "Open the event sheet to edit recurring or multi-day details",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    )
    .accessibilityLabel(
      String(
        localized: "calendar.weekgrid.edit_hint.a11y",
        defaultValue: "Edit in event sheet",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    )
    .accessibilityHint(
      String(
        localized: "calendar.weekgrid.edit_hint.a11y_hint",
        defaultValue:
          "Recurring and multi-day events cannot be dragged or resized in the calendar grid.",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    )
    .accessibilityIdentifier("calendar.weekgrid.editSheetHint")
  }

  /// One edge grip of a timed block. `visible` fades the mark itself, which is
  /// centered on the block's edge; the transparent hit area behind it is always
  /// present so the resize cursor and gesture do not wait on the grip's
  /// appearance. A click on the hit area without a drag calls `select`, as a
  /// click on the block does. `leadingInset` keeps the hit area off the block's
  /// leading edge, where a task block's completion circle sits; the mark does
  /// not move.
  func resizeHandle(
    alignment: VerticalAlignment,
    color: Color,
    visible: Bool,
    leadingInset: CGFloat = 0,
    gesture: some Gesture,
    select: @escaping () -> Void
  ) -> some View {
    Color.clear
      .frame(height: CalendarEventBlockMetrics.resizeHandleHitHeight)
      .contentShape(Rectangle())
      .calendarResizeCursor()
      .gesture(gesture)
      .simultaneousGesture(TapGesture().onEnded { select() })
      .padding(.leading, leadingInset)
      .overlay(alignment: alignment == .top ? .top : .bottom) {
        Rectangle()
          .fill(color.opacity(0.55))
          .frame(width: CalendarEventBlockMetrics.resizeHandleWidth, height: 2)
          .clipShape(Capsule())
          .padding(alignment == .top ? .top : .bottom, 1)
          .opacity(visible ? 1 : 0)
          .reduceMotionAnimation(.easeInOut(duration: 0.12), value: visible)
          .allowsHitTesting(false)
      }
      .accessibilityHidden(true)
  }
}

/// How far a block being dragged has moved and resized from where it lies in
/// its column, read from the grid's reschedule draft. Event blocks and timed
/// task blocks use all three parts.
struct CalendarBlockMovePreview {
  let move: CGSize
  let resizeBottom: CGFloat
  let resizeTop: CGFloat

  init(draft: CalendarWeekGridView.RescheduleDraft?) {
    switch draft?.kind {
    case .move:
      move = draft?.translation ?? .zero
      resizeBottom = 0
      resizeTop = 0
    case .resize:
      move = .zero
      resizeBottom = draft?.translation.height ?? 0
      resizeTop = 0
    case .resizeTop:
      move = .zero
      resizeBottom = 0
      resizeTop = draft?.translation.height ?? 0
    case nil:
      move = .zero
      resizeBottom = 0
      resizeTop = 0
    }
  }
}
