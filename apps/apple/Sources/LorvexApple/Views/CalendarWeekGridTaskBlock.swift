import LorvexCore
import SwiftUI

/// A timed task on the week grid, drawn at its time in the accent tint. It
/// borrows the task row's vocabulary rather than the event block's: a leading
/// circle that completes the task, and the calendar task surface
/// (`lorvexCalendarTaskSurface`, a hollow dashed outline) instead of an
/// event's solid fill and rail, so time set aside for the user's own work never
/// reads like a meeting. The block opens the task; the task's time is set in
/// its detail or by suggested times on Today.
extension CalendarWeekGridView {
  func taskBlock(
    _ block: CalendarGridTaskBlock, on day: CalendarGridDay, columnWidth: CGFloat
  ) -> some View {
    let laneWidth = columnWidth / CGFloat(min(block.laneCount, maxDisplayedLanes))
    let y = CGFloat(block.startMin) / 60 * hourHeight
    // The drawn end carries the model's minimum; see `eventBlock`.
    let height = CGFloat(block.drawnEndMin - block.startMin) / 60 * hourHeight
    let color = LorvexDesign.Palette.accent
    let isRunning = isRunningNow(block, on: day) && !block.isDone
    let isSelected = store.selectedTaskID == block.task.id

    return LorvexCalendarBlockText(
      title: block.task.title,
      time: lorvexClockTimeLabel(minutes: block.startMin),
      range: lorvexClockRangeLabel(startMinutes: block.startMin, endMinutes: block.endMin),
      isDone: block.isDone,
      verticalPadding: CalendarEventBlockMetrics.verticalPadding
    ) {
      taskCompletionCircle(for: block.task)
        .accessibilityIdentifier("calendar.weekgrid.taskBlock.complete")
    }
    .padding(.leading, 3)
    .padding(.trailing, CalendarEventBlockMetrics.horizontalPadding)
    .frame(
      width: max(laneWidth - CalendarEventBlockMetrics.laneGap, 8),
      height: height,
      alignment: .topLeading
    )
    .clipped()
    .lorvexCalendarTaskSurface(
      isDone: block.isDone,
      isEmphasized: isRunning || isSelected,
      cornerRadius: CalendarEventBlockMetrics.cornerRadius,
      lineWidth: isSelected ? 1.5 : 1,
      hidesContentBeneath: true)
    .calendarPointingHandCursor()
    .contentShape(Rectangle())
    .zIndex(isSelected ? 2 : 1)
    .offset(x: CGFloat(block.lane) * laneWidth, y: y)
    .shadow(
      color: isSelected ? color.opacity(0.35) : .clear,
      radius: isSelected ? CalendarEventBlockMetrics.selectedShadowRadius : 0,
      y: 2)
    .onTapGesture { openTask(block.task) }
    .focusable(true)
    .onKeyPress(.return) {
      openTask(block.task)
      return .handled
    }
    .onKeyPress(.space) {
      openTask(block.task)
      return .handled
    }
    .contextMenu {
      Button(
        String(localized: "calendar.task.open", defaultValue: "Open Task", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "arrow.up.forward.square"
      ) { openTask(block.task) }
      Button(
        taskCompletionLabel(isDone: block.isDone),
        systemImage: block.isDone ? "arrow.uturn.backward.circle" : "checkmark.circle"
      ) { toggleCompletion(of: block.task) }
    }
    .accessibilityAddTraits(.isButton)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityLabel(taskBlockAccessibilityLabel(block))
    .accessibilityIdentifier("calendar.weekgrid.taskBlock")
  }

  /// The leading circle a task carries on the grid, in a timed block or an
  /// all-day pill: the same checkbox a task row carries, so completing a task
  /// from the calendar is one click. A done task shows the filled circle with
  /// its check. The circle keeps its glyph's own height, so it sits on the
  /// baseline of the title beside it.
  func taskCompletionCircle(for task: LorvexTask) -> some View {
    let isDone = task.status == .completed
    let label = taskCompletionLabel(isDone: isDone)
    return Button {
      toggleCompletion(of: task)
    } label: {
      Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
        .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
        .foregroundStyle(LorvexDesign.Palette.accent.opacity(isDone ? 0.7 : 0.85))
        .frame(width: 16)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(label)
    .accessibilityLabel(label)
  }

  /// The name of the action that completes an open task or reopens a done one.
  func taskCompletionLabel(isDone: Bool) -> String {
    isDone
      ? String(localized: "common.reopen", defaultValue: "Reopen", table: "Localizable", bundle: LorvexL10n.bundle)
      : String(localized: "common.complete", defaultValue: "Complete", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  func toggleCompletion(of task: LorvexTask) {
    Task { await store.toggleCalendarTaskCompletion(id: task.id, undoManager: undoManager) }
  }

  /// True while the clock sits inside this block on today's column, so a
  /// running time reads the same on the grid as on Today.
  private func isRunningNow(_ block: CalendarGridTaskBlock, on day: CalendarGridDay) -> Bool {
    guard day.dayKey == store.logicalTodayDateString, let now = store.nowMinutesInProductDay
    else { return false }
    return block.startMin <= now && now < block.endMin
  }

  func taskBlockAccessibilityLabel(_ block: CalendarGridTaskBlock) -> String {
    String(
      format: String(
        localized: "calendar.task_block.a11y",
        defaultValue: "Task %@, %@ to %@",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      block.task.title,
      lorvexClockTimeLabel(minutes: block.startMin),
      lorvexClockTimeLabel(minutes: block.endMin))
  }
}
