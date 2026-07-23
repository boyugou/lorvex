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
    let laneWidth = columnWidth / CGFloat(block.laneCount)
    let y = CGFloat(block.startMin) / 60 * hourHeight
    let height = max(CGFloat(block.endMin - block.startMin) / 60 * hourHeight, 18)
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
    return VStack(alignment: .leading, spacing: 1) {
      Text(block.event.title)
        .font(LorvexDesign.Typography.tertiaryText.weight(.medium)).lineLimit(2)
      if height > 34, let time = block.event.startTime {
        Text(time).font(LorvexDesign.Typography.tertiaryText).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 5).padding(.vertical, 3)
    .frame(width: max(laneWidth - 2, 10), height: height, alignment: .topLeading)
    .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
    .overlay(alignment: .leading) {
      Rectangle().fill(color).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 1.5))
    }
    .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.35), lineWidth: 0.5))
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
    // rather than a hand-rolled generator; no-ops on visionOS (see
    // MobileSensoryFeedback.swift).
    .lorvexSensoryFeedback(.impact(weight: .medium), trigger: active) { _, isActive in isActive }
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
            bundle: MobileL10n.bundle), start))
      if let end = block.event.endTime {
        parts.append(
          String(
            format: String(
              localized: "calendar.block.to.a11y", defaultValue: "to %@", table: "Localizable",
              bundle: MobileL10n.bundle), end))
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
