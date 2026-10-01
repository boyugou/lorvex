import LorvexCore
import SwiftUI

extension MobileCalendarDayColumn {
  func eventBlock(
    _ block: CalendarGridTimedBlock,
    day: CalendarGridDay,
    dayIndex: Int,
    allDays: [CalendarGridDay],
    columnWidth: CGFloat
  ) -> some View {
    let laneBand = max(
      columnWidth - LorvexDesign.CalendarMetrics.laneTrailingInset(columnWidth: columnWidth), 1)
    let laneWidth = laneBand / CGFloat(block.laneCount)
    let y = CGFloat(block.startMin) / 60 * hourHeight
    // The drawn end carries the model's minimum height; a floor here would
    // only run a short block under the one that starts right after it.
    let height = CGFloat(block.drawnEndMin - block.startMin) / 60 * hourHeight
    let isTight = height < LorvexDesign.CalendarMetrics.tightBlockHeight
    let isCompact = laneWidth < LorvexDesign.CalendarMetrics.compactLaneWidth
    let color = eventColor(block.event)
    let activeDrag = dragState?.eventID == block.event.id ? dragState : nil
    let active = activeDrag != nil
    let dragOffsetX: CGFloat = activeDrag?.translationX ?? 0
    let dragOffsetY: CGFloat = activeDrag?.translationY ?? 0
    let isMultiDay =
      block.event.endDate != nil && block.event.endDate != block.event.startDate
    let isReschedulable =
      onReschedule != nil && block.event.editable && !block.event.allDay
      && !block.event.supportsScopedMutation && !isMultiDay
    let title = Text(block.event.title)
      .font(LorvexDesign.Typography.tertiaryText.weight(.medium)).lineLimit(2)
    let start = block.event.startTime.map(lorvexClockTimeLabel)
    // A multi-day event's piece of one day is not its time, so it keeps its
    // start alone.
    let range =
      isMultiDay
      ? nil : lorvexClockRangeLabel(startMinutes: block.startMin, endMinutes: block.endMin)
    // The text clears the 3pt color rail on the leading edge. A compact
    // block takes the trailing side down to 1pt instead, so its title keeps
    // every point of the narrow lane.
    let leadingPadding: CGFloat = 5
    let trailingPadding: CGFloat = isCompact ? 1 : 5
    let verticalPadding: CGFloat = isTight ? 0 : 3
    return blockContent(
      isCompact: isCompact, eventTitle: block.event.title, title: title, start: start, range: range
    )
    .padding(.leading, leadingPadding).padding(.trailing, trailingPadding)
    .padding(.vertical, verticalPadding)
    .frame(width: max(laneWidth - 2, 10), height: height, alignment: .topLeading)
    .clipped()
    .lorvexOpaqueTintBackground(
      color.opacity(0.22), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    .overlay(alignment: .leading) {
      Rectangle().fill(color).frame(width: 3).clipShape(
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    }
    .overlay(RoundedRectangle(cornerRadius: LorvexDesign.Radius.s).stroke(color.opacity(0.35), lineWidth: 0.5))
    .contentShape(Rectangle())
    .zIndex(1)
    .offset(x: CGFloat(block.lane) * laneWidth + dragOffsetX, y: y + dragOffsetY)
    .opacity(active ? 0.82 : 1)
    .shadow(color: active ? .black.opacity(0.18) : .clear, radius: 6, y: 2)
    .gesture(
      isReschedulable
        ? rescheduleGesture(
          for: block, day: day, dayIndex: dayIndex,
          allDays: allDays, columnWidth: columnWidth)
        : nil
    )
    .onTapGesture { if block.event.editable { onTapEvent(block.event) } }
    .contextMenu {
      if block.event.editable {
        Button {
          onTapEvent(block.event)
        } label: {
          Label(
            String(
              localized: "common.edit", defaultValue: "Edit", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "pencil")
        }

        Button(role: .destructive) {
          Task { _ = await onDeleteEvent(block.event) }
        } label: {
          Label(
            String(
              localized: "common.delete", defaultValue: "Delete", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "trash")
        }
      }
    }
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel(blockAccessibilityLabel(block))
    // Haptic pickup when the long-press latches this block for reschedule, via
    // SwiftUI's native feedback (the same idiom the mobile task/habit rows use)
    // rather than a hand-rolled generator.
    .lorvexSensoryFeedback(.impact(weight: .medium), trigger: active) { _, isActive in isActive }
  }


  /// A compact block's title alone, or the title with its time.
  @ViewBuilder
  private func blockContent(
    isCompact: Bool, eventTitle: String, title: some View, start: String?, range: String?
  ) -> some View {
    if isCompact {
      MobileCalendarCompactBlockTitle(eventTitle)
    } else {
      fullContent(title: title, start: start, range: range)
    }
  }

  /// A block's title with its time: under the title where both fit (the
  /// range, or the start when the range is too wide); in a block too short for
  /// that, after the title on one line when both fit whole, and otherwise the
  /// title alone rather than half a line of time.
  @ViewBuilder
  private func fullContent(title: some View, start: String?, range: String?) -> some View {
    ViewThatFits(in: .vertical) {
      if let start {
        VStack(alignment: .leading, spacing: 1) {
          title
          ViewThatFits(in: .horizontal) {
            if let range { MobileCalendarBlockTime(range) }
            MobileCalendarBlockTime(start)
          }
        }
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            title.lineLimit(1)
            MobileCalendarBlockTime(range ?? start)
          }
          title
        }
      }
      title
    }
  }

  /// Long-press-then-drag gesture: vertical translation shifts start time;
  /// horizontal translation snaps to adjacent visible-day columns on 3-day mode.
  func rescheduleGesture(
    for block: CalendarGridTimedBlock,
    day: CalendarGridDay,
    dayIndex: Int,
    allDays: [CalendarGridDay],
    columnWidth: CGFloat
  ) -> some Gesture {
    let lp = LongPressGesture(minimumDuration: 0.30)
    let drag = DragGesture(minimumDistance: 0)
    return lp.sequenced(before: drag)
      .onChanged { value in
        switch value {
        case .first:
          if dragState?.eventID != block.event.id {
            dragState = DragState(eventID: block.event.id, translationX: 0, translationY: 0)
          }
        case .second(_, let dragValue):
          let dx = allDays.count > 1 ? (dragValue?.translation.width ?? 0) : 0
          let dy = dragValue?.translation.height ?? 0
          dragState = DragState(eventID: block.event.id, translationX: dx, translationY: dy)
        }
      }
      .onEnded { value in
        defer { dragState = nil }
        guard case .second(_, let dragValue) = value, let dragValue else { return }
        let totalMinutes = block.endMin - block.startMin
        let rawDelta = Int((dragValue.translation.height / hourHeight * 60).rounded())
        let snappedMinutes = (rawDelta / Self.snapMinutes) * Self.snapMinutes
        let columnDelta =
          allDays.count > 1 && columnWidth > 0
          ? Int((dragValue.translation.width / columnWidth).rounded()) : 0
        let newColumnIndex = max(0, min(allDays.count - 1, dayIndex + columnDelta))
        let dayShifted = newColumnIndex != dayIndex
        guard snappedMinutes != 0 || dayShifted else { return }
        let clampedStart = max(
          0, min(24 * 60 - totalMinutes, block.startMin + snappedMinutes))
        let targetDay = allDays[newColumnIndex].date
        onReschedule?(block.event, targetDay, clampedStart)
      }
  }

  func eventColor(_ event: CalendarTimelineEvent) -> Color {
    Color(lorvexHex: event.color) ?? .accentColor
  }

  private func blockAccessibilityLabel(_ block: CalendarGridTimedBlock) -> String {
    var parts = [block.event.title]
    if let start = block.event.startTime {
      parts.append(
        String(
          format: String(
            localized: "calendar.block.from.a11y", defaultValue: "from %@", table: "Localizable",
            bundle: MobileL10n.bundle), lorvexClockTimeLabel(start)))
      if let end = block.event.endTime {
        parts.append(
          String(
            format: String(
              localized: "calendar.block.to.a11y", defaultValue: "to %@", table: "Localizable",
              bundle: MobileL10n.bundle), lorvexClockTimeLabel(end)))
      }
    }
    if let location = block.event.location, !location.isEmpty {
      parts.append(
        String(
          format: String(
            localized: "calendar.block.at.a11y", defaultValue: "at %@", table: "Localizable",
            bundle: MobileL10n.bundle), location))
    }
    return parts.joined(separator: " ")
  }
}
