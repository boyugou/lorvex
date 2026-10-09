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
    let isReschedulable =
      onReschedule != nil && block.event.editable && !block.event.allDay
      && !block.event.supportsScopedMutation && !block.event.isMultiDay
    // The text clears the 3pt color rail on the leading edge. A compact
    // block takes the trailing side down to 1pt instead, so its title keeps
    // every point of the narrow lane.
    let leadingPadding: CGFloat = 5
    let trailingPadding: CGFloat = isCompact ? 1 : 5
    return blockContent(
      isCompact: isCompact, isTight: isTight, title: block.event.title, time: block.timeLabel,
      range: block.rangeLabel
    )
    .padding(.leading, leadingPadding).padding(.trailing, trailingPadding)
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
    .onTapGesture { if block.event.editable { onTapEvent(block.event) } }
    // A block that lifts for rescheduling carries an empty menu, which attaches
    // no menu interaction: a real one would hold back the lift's press
    // (`MobileCalendarEventLift`). Its editor offers Delete, and VoiceOver gets
    // Delete as an action below.
    .contextMenu {
      if block.event.editable && !isReschedulable {
        Button {
          onTapEvent(block.event)
        } label: {
          Label(
            String(
              localized: "common.edit", defaultValue: "Edit", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "pencil")
        }

        deleteButton(for: block.event)
      }
    }
    .lorvexEventLift(
      rescheduleLift(
        for: block, dayIndex: dayIndex, allDays: allDays, columnWidth: columnWidth,
        isEnabled: isReschedulable)
    )
    // One VoiceOver element per block, as for a task block: the label on a
    // container with several texts would land on the title and on the time
    // separately and read the block twice. An event that cannot be edited
    // opens nothing, so it is not a button.
    .accessibilityElement(children: .ignore)
    .accessibilityAddTraits(block.event.editable ? .isButton : [])
    .accessibilityLabel(
      blockAccessibilityLabel(block, namingDayOf: allDays.count > 1 ? day : nil)
    )
    .accessibilityAction { if block.event.editable { onTapEvent(block.event) } }
    .accessibilityActions {
      if block.event.editable && isReschedulable { deleteButton(for: block.event) }
    }
    .accessibilitySortPriority(Self.accessibilitySortPriority(startMin: block.startMin))
    // Haptic pickup when the long-press latches this block for reschedule, via
    // SwiftUI's native feedback (the same idiom the mobile task/habit rows use)
    // rather than a hand-rolled generator.
    .lorvexSensoryFeedback(.impact(weight: .medium), trigger: active) { _, isActive in isActive }
  }

  /// A compact block's title alone, wrapping as far as the block is tall; any
  /// other block's title with its time, arranged to fit the block
  /// (``LorvexCalendarBlockText``).
  @ViewBuilder
  private func blockContent(
    isCompact: Bool, isTight: Bool, title: String, time: String?, range: String?
  ) -> some View {
    if isCompact {
      LorvexCalendarCompactBlockTitle(title)
        .padding(.vertical, isTight ? 0 : 3)
    } else {
      LorvexCalendarBlockText(title: title, time: time, range: range, verticalPadding: 3)
    }
  }

  /// The block's reschedule lift: a finger that rests on the block lifts it,
  /// vertical travel then shifts its start time, and on a page of several days
  /// horizontal travel moves it to another day's column. The block is written
  /// only when it lands somewhere new (``CalendarGridMove/landing``).
  func rescheduleLift(
    for block: CalendarGridTimedBlock,
    dayIndex: Int,
    allDays: [CalendarGridDay],
    columnWidth: CGFloat,
    isEnabled: Bool
  ) -> MobileCalendarEventLift {
    MobileCalendarEventLift(
      isEnabled: isEnabled,
      onMove: { travel in
        dragState = DragState(
          eventID: block.event.id, translationX: allDays.count > 1 ? travel.width : 0,
          translationY: travel.height)
      },
      onDrop: { travel in
        defer { dragState = nil }
        let landing = CalendarGridMove.landing(
          startMinute: block.startMin, duration: block.endMin - block.startMin,
          translation: travel, hourHeight: hourHeight, columnWidth: columnWidth,
          dayIndex: dayIndex, dayCount: allDays.count)
        guard !landing.isUnchanged else { return }
        onReschedule?(block.event, allDays[dayIndex + landing.dayShift].date, landing.startMinute)
      },
      onCancel: { dragState = nil })
  }

  private func deleteButton(for event: CalendarTimelineEvent) -> some View {
    Button(role: .destructive) {
      Task { _ = await onDeleteEvent(event) }
    } label: {
      Label(
        String(
          localized: "common.delete", defaultValue: "Delete", table: "Localizable",
          bundle: MobileL10n.bundle), systemImage: "trash")
    }
  }

  func eventColor(_ event: CalendarTimelineEvent) -> Color {
    Color(lorvexHex: event.color) ?? .accentColor
  }

  /// The block's VoiceOver label: title, times and place, followed by the
  /// day when `namingDayOf` is given (``MobileCalendarBlockLabel``).
  private func blockAccessibilityLabel(
    _ block: CalendarGridTimedBlock, namingDayOf day: CalendarGridDay?
  ) -> String {
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
    return MobileCalendarBlockLabel.appendingDay(
      parts.joined(separator: " "), of: day?.date, calendar: calendar)
  }
}
