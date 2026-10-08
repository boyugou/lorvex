import LorvexCore
import SwiftUI

/// A timed task on the phone's day grid: the task's time on its planned day,
/// drawn on the time axis in the accent tint. It borrows the task row's
/// vocabulary rather than the event block's — a leading ring that completes
/// the task and the calendar task surface (`lorvexCalendarTaskSurface`, a
/// hollow dashed outline) instead of an event's solid fill and rail — so a
/// hold on the calendar and an intention for the day never read alike. The
/// block opens its task, where the time is changed or cleared. A compact
/// block (``LorvexDesign/CalendarMetrics/compactLaneWidth``) drops the ring,
/// which would leave no room for the title and is too small to aim at; its
/// context menu still completes the task.
extension MobileCalendarDayColumn {
  func taskBlock(
    _ block: CalendarGridTaskBlock, day: CalendarGridDay, columnWidth: CGFloat
  ) -> some View {
    let laneBand = max(
      columnWidth - LorvexDesign.CalendarMetrics.laneTrailingInset(columnWidth: columnWidth), 1)
    let laneWidth = laneBand / CGFloat(block.laneCount)
    let y = CGFloat(block.startMin) / 60 * hourHeight
    // The drawn end carries the model's minimum height; see `eventBlock`.
    let height = CGFloat(block.drawnEndMin - block.startMin) / 60 * hourHeight
    let isTight = height < LorvexDesign.CalendarMetrics.tightBlockHeight
    let isCompact = laneWidth < LorvexDesign.CalendarMetrics.compactLaneWidth
    let isRunning = isRunningNow(block, day) && !block.isDone
    let toggleLabel = MobileTaskActionCopy.completionToggle(isDone: block.isDone)
    return Group {
      if isCompact {
        LorvexCalendarCompactBlockTitle(block.task.title, isDone: block.isDone)
          .padding(.leading, 1)
          .padding(.vertical, isTight ? 0 : 3)
      } else {
        LorvexCalendarBlockText(
          title: block.task.title,
          time: lorvexClockTimeLabel(minutes: block.startMin),
          range: lorvexClockRangeLabel(startMinutes: block.startMin, endMinutes: block.endMin),
          isDone: block.isDone,
          verticalPadding: 3,
          accessorySpacing: 2
        ) {
          MobileCalendarTaskRing(
            isDone: block.isDone, font: LorvexDesign.Typography.secondaryText, width: 20
          ) {
            onToggleTask(block.task)
          }
        }
      }
    }
    .padding(.leading, 2)
    .padding(.trailing, isCompact ? 2 : 5)
    .frame(width: max(laneWidth - 2, 10), height: height, alignment: .topLeading)
    .clipped()
    .lorvexCalendarTaskSurface(
      isDone: block.isDone,
      isEmphasized: isRunning,
      cornerRadius: LorvexDesign.Radius.s,
      hidesContentBeneath: true)
    .contentShape(Rectangle())
    .zIndex(1)
    .offset(x: CGFloat(block.lane) * laneWidth, y: y)
    .onTapGesture { onTapTask(block.task) }
    .contextMenu {
      Button {
        onTapTask(block.task)
      } label: {
        Label(MobileCalendarTaskCopy.open, systemImage: "arrow.up.forward.square")
      }
      Button {
        onToggleTask(block.task)
      } label: {
        Label(toggleLabel, systemImage: MobileCalendarTaskCopy.toggleSystemImage(isDone: block.isDone))
      }
    }
    // One VoiceOver element per block: the label names the task and its slot,
    // the default action opens it, and the ring's completion is a named action
    // rather than a second 24pt element to hunt for inside the block.
    .accessibilityElement(children: .ignore)
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel(taskBlockAccessibilityLabel(block, namingDayOf: dayCount > 1 ? day : nil))
    .accessibilityAction { onTapTask(block.task) }
    .accessibilityAction(named: Text(toggleLabel)) { onToggleTask(block.task) }
    .accessibilitySortPriority(Self.accessibilitySortPriority(startMin: block.startMin))
    .accessibilityIdentifier("mobileCalendar.taskBlock")
  }

  /// The block's VoiceOver label: task, start and end, followed by the day when
  /// `namingDayOf` is given (``MobileCalendarBlockLabel``).
  private func taskBlockAccessibilityLabel(
    _ block: CalendarGridTaskBlock, namingDayOf day: CalendarGridDay?
  ) -> String {
    MobileCalendarBlockLabel.appendingDay(
      String(
        format: String(
          localized: "calendar.task_block.a11y",
          defaultValue: "Task %@, %@ to %@",
          table: "Localizable",
          bundle: MobileL10n.bundle),
        block.task.title,
        lorvexClockTimeLabel(minutes: block.startMin),
        lorvexClockTimeLabel(minutes: block.endMin)),
      of: day?.date, calendar: calendar)
  }
}
