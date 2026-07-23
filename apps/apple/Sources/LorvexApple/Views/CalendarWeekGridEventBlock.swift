import LorvexCore
import SwiftUI

private enum CalendarEventBlockMetrics {
  static let minimumHeight: CGFloat = 16
  static let compactHeightThreshold: CGFloat = 28
  static let timeHeightThreshold: CGFloat = 34
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
    let baseHeight = max(
      CGFloat(block.endMin - block.startMin) / 60 * hourHeight,
      CalendarEventBlockMetrics.minimumHeight
    )
    let color = eventColor(block.event)
    let active = rescheduleDraft?.eventID == block.event.id ? rescheduleDraft : nil
    // The block whose inspector is open reads as selected: a stronger fill, a
    // full-color ring, and a soft lift. This gives the open inspector a visual
    // anchor and makes the tap-again-to-close toggle discoverable.
    let isSelected = store.selectedCalendarEventID == block.event.id
    let preview = CalendarEventBlockPreview(draft: active)
    let renderedHeight = max(
      baseHeight + preview.resizeBottom - preview.resizeTop,
      hourHeight / 4
    )
    let isMultiDay =
      block.event.endDate != nil && block.event.endDate != block.event.startDate
    let isEditable =
      block.event.editable && !block.event.allDay && !block.event.supportsScopedMutation
      && !isMultiDay

    return CalendarEventBlockContent(
      title: block.event.title,
      time: block.event.startTime.map(lorvexClockTimeLabel),
      renderedHeight: renderedHeight
    )
    .padding(.horizontal, CalendarEventBlockMetrics.horizontalPadding)
    .padding(.vertical, CalendarEventBlockMetrics.verticalPadding)
    .frame(
      width: max(laneWidth - CalendarEventBlockMetrics.laneGap, 8),
      height: renderedHeight,
      alignment: .topLeading
    )
    .background(
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
          gesture: resizeTopGesture(for: block),
          block: block)
      }
    }
    .overlay(alignment: .bottom) {
      if isEditable {
        resizeHandle(
          alignment: .bottom,
          color: color,
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
    .padding(3)
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

  private func resizeHandle(
    alignment: VerticalAlignment,
    color: Color,
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

private struct CalendarEventBlockContent: View {
  let title: String
  let time: String?
  let renderedHeight: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(titleLineLimit)
        .fixedSize(horizontal: false, vertical: true)

      if renderedHeight >= CalendarEventBlockMetrics.timeHeightThreshold, let time {
        Text(time)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.top, 1)
      }

      Spacer(minLength: 0)
    }
  }

  private var titleLineLimit: Int {
    renderedHeight < CalendarEventBlockMetrics.compactHeightThreshold ? 1 : 2
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
