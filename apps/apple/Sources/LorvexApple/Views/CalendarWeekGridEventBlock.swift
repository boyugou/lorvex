import LorvexCore
import SwiftUI

enum CalendarEventBlockMetrics {
  static let verticalPadding: CGFloat = 2
  static let horizontalPadding: CGFloat = 4
  static let laneGap: CGFloat = 2
  static let cornerRadius: CGFloat = CalendarWeekGridMetrics.eventCornerRadius
  static let accentRailWidth: CGFloat = 2.5
  static let activeShadowRadius: CGFloat = 7
  static let selectedShadowRadius: CGFloat = 5
  static let resizeHandleHitHeight: CGFloat = 8
  static let resizeHandleWidth: CGFloat = 18
}

extension CalendarWeekGridView {
  func eventBlock(
    _ block: CalendarGridTimedBlock,
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
    let active = rescheduleDraft?.eventID == block.event.id ? rescheduleDraft : nil
    // The block whose inspector is open reads as selected: a stronger fill, a
    // full-color ring, and a soft lift. This gives the open inspector a visual
    // anchor and makes the tap-again-to-close toggle discoverable.
    let isSelected = store.selectedCalendarEventID == block.event.id
    let preview = CalendarEventBlockPreview(draft: active)
    // A resize in progress cannot shrink the block below a quarter hour.
    let renderedHeight =
      active == nil
      ? baseHeight
      : max(baseHeight + preview.resizeBottom - preview.resizeTop, hourHeight / 4)
    let isMultiDay =
      block.event.endDate != nil && block.event.endDate != block.event.startDate
    let isEditable =
      block.event.editable && !block.event.allDay && !block.event.supportsScopedMutation
      && !isMultiDay
    let showsResizeGrips = isSelected || hoveredEventID == block.event.id

    return LorvexCalendarBlockText(
      title: block.event.title,
      start: block.event.startTime.map(lorvexClockTimeLabel),
      // A multi-day event's piece of one day is not its time, so it keeps its
      // start alone.
      range: isMultiDay
        ? nil : lorvexClockRangeLabel(startMinutes: block.startMin, endMinutes: block.endMin),
      verticalPadding: CalendarEventBlockMetrics.verticalPadding
    )
    .padding(.horizontal, CalendarEventBlockMetrics.horizontalPadding)
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
        hoveredEventID = block.event.id
      } else if hoveredEventID == block.event.id {
        hoveredEventID = nil
      }
    }
    .overlay(alignment: .topTrailing) {
      if block.event.editable && !isEditable {
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
          block: block)
      }
    }
    .overlay(alignment: .bottom) {
      if isEditable {
        resizeHandle(
          alignment: .bottom,
          color: color,
          visible: showsResizeGrips,
          gesture: resizeGesture(for: block),
          block: block)
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
    .accessibilityAddTraits(.isButton)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityLabel(blockAccessibilityLabel(block))
    .contextMenu { eventBlockContextMenu(block.event) }
  }

  /// Right-click actions for an event block. Editable (Lorvex-owned) events get
  /// Edit + Delete; imported events only get "Open Details" since they can't be
  /// mutated here.
  @ViewBuilder
  func eventBlockContextMenu(_ event: CalendarTimelineEvent) -> some View {
    Button {
      selectEvent(event)
    } label: {
      Label(
        String(
          localized: "calendar.event.open_details", defaultValue: "Open Details",
          table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "sidebar.right")
    }
    if event.editable {
      Button {
        editEvent(event)
      } label: {
        Label(
          String(
            localized: "common.edit", defaultValue: "Edit", table: "Localizable",
            bundle: LorvexL10n.bundle), systemImage: "pencil")
      }
      Button(role: .destructive) {
        requestDeleteEvent(event)
      } label: {
        Label(
          String(
            localized: "common.delete", defaultValue: "Delete", table: "Localizable",
            bundle: LorvexL10n.bundle), systemImage: "trash")
      }
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

  /// One edge grip. `visible` fades the mark itself; the transparent hit area
  /// above it is always present so the resize cursor and gesture do not wait on
  /// the grip's appearance.
  private func resizeHandle(
    alignment: VerticalAlignment,
    color: Color,
    visible: Bool,
    gesture: some Gesture,
    block: CalendarGridTimedBlock
  ) -> some View {
    Color.clear
      .frame(height: CalendarEventBlockMetrics.resizeHandleHitHeight)
      .contentShape(Rectangle())
      .overlay(alignment: alignment == .top ? .top : .bottom) {
        Rectangle()
          .fill(color.opacity(0.55))
          .frame(width: CalendarEventBlockMetrics.resizeHandleWidth, height: 2)
          .clipShape(Capsule())
          .padding(alignment == .top ? .top : .bottom, 1)
          .opacity(visible ? 1 : 0)
          .animation(.easeInOut(duration: 0.12), value: visible)
      }
      .calendarResizeCursor()
      .gesture(gesture)
      .simultaneousGesture(
        TapGesture().onEnded { selectEvent(block.event) }
      )
      .accessibilityHidden(true)
  }

  private func blockAccessibilityLabel(_ block: CalendarGridTimedBlock) -> String {
    calendarEventAccessibilityLabel(
      title: block.event.title,
      allDay: false,
      startTime: block.event.startTime.map(lorvexClockTimeLabel),
      endTime: block.event.endTime.map(lorvexClockTimeLabel),
      location: block.event.location,
      source: block.event.source
    )
  }
}

private struct CalendarEventBlockPreview {
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
