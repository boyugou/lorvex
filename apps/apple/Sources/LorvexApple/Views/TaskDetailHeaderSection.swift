import LorvexCore
import SwiftUI

extension TaskDetailView {
  /// Title block: the task's completion circle, the inline title, when the task's time ends
  /// while that time is running, and the status facts that are true right now.
  ///
  /// The list and priority live in the property sentence below, and the
  /// started state in the Start toggle under the header, so this block does
  /// not repeat them. Nothing here reports save state: the panel autosaves.
  /// The inspector's ✕ is the only control beside the title, so a long title
  /// wraps at the width the habit inspector's name has; Pin as Sticky is in the
  /// More menu under the header.
  func headerSection(task: LorvexTask) -> some View {
    InspectorPanel(accessibilityIdentifier: "task.detail.header.panel", chrome: .header) {
      HStack(alignment: .top, spacing: LorvexDesign.Spacing.s) {
        completionCircle(task: task)

        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
          TextField(
            String(localized: "task_detail.header.title_placeholder", defaultValue: "Title", table: "Localizable", bundle: LorvexL10n.bundle),
            text: taskTitleBinding(for: task),
            axis: .vertical
          )
          .font(LorvexDesign.Typography.detailTitle)
          .textFieldStyle(.plain)
          // No upper cap: the inspector scrolls, and a cap would clip the rest
          // of a long title with no ellipsis to say so.
          .lineLimit(1...)
          .fixedSize(horizontal: false, vertical: true)
          .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
          .focused($titleFieldFocused)
          .accessibilityLabel(String(localized: "task_detail.header.title_a11y", defaultValue: "Task title", table: "Localizable", bundle: LorvexL10n.bundle))
          .accessibilityIdentifier("task.detail.title")

          if let until = runningLine(task: task) {
            Text(until)
              .font(LorvexDesign.Typography.pageLabel)
              .foregroundStyle(LorvexDesign.Palette.accent)
              .accessibilityIdentifier("task.detail.header.until")
          }

          statusPills(task: task)
        }

        hideInspectorButton
      }
    }
  }

  /// The task's completion circle: the same priority-tinted glyph as its
  /// row in every list, set larger, so it reads as the control that checks
  /// the task off rather than a decoration.
  @ViewBuilder
  private func completionCircle(task: LorvexTask) -> some View {
    let isDone = task.status == .completed
    Button {
      Task { await store.toggleTaskCompletion(task, undoManager: undoManager) }
    } label: {
      Image(systemName: task.statusCircleGlyph)
        .font(LorvexDesign.Typography.screenTitle.weight(.regular))
        .foregroundStyle(task.statusCircleStyle)
        .contentTransition(.symbolEffect(.replace))
        .reduceMotionBounce(value: isDone)
        // As tall as the title's first line, so the circle sits on that line
        // whatever the title's length.
        .frame(width: 32, height: 24)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(task.status == .cancelled || task.status == .someday)
    .help(TaskDisplayText.completionToggle(isDone: isDone))
    .accessibilityLabel(TaskDisplayText.completionToggle(isDone: isDone))
    .accessibilityIdentifier("task.detail.completionCircle")
  }

  /// The task on Today while its time today contains the clock; nil for any
  /// other task. Read from the whole day, which the search field does not
  /// narrow.
  private func runningItem(task: LorvexTask) -> LorvexCalmToday.Item? {
    guard task.status.isActionable else { return nil }
    return store.calmToday.items.first { $0.id == task.id && $0.isRunning }
  }

  /// "Until 3:00 PM" while the task's time is running; nil otherwise, since
  /// the property sentence already states the time.
  private func runningLine(task: LorvexTask) -> String? {
    runningItem(task: task)?.time.map { TodayCalmCopy.untilLabel(end: $0.upperBound) }
  }

  /// Facts about the task's current state, never editable fields. Priority lives
  /// in the property sentence; repeating it here would be the same value in two
  /// places.
  @ViewBuilder
  private func statusPills(task: LorvexTask) -> some View {
    let isBlocked = store.isBlocked(task)
    if store.taskDetailDueIsOverdue || isBlocked {
      HStack(spacing: LorvexDesign.Spacing.xs) {
        if store.taskDetailDueIsOverdue {
          TaskDetailStatusPill(
            text: String(localized: "task_detail.pill.overdue", defaultValue: "Overdue", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "clock.badge.exclamationmark",
            tint: LorvexDesign.Palette.overdue)
        }
        if isBlocked {
          TaskDetailStatusPill(
            text: TaskDisplayText.blocked,
            systemImage: "lock.fill",
            tint: LorvexDesign.Palette.blocked)
        }
      }
      .padding(.top, 1)
      .accessibilityIdentifier("task.detail.header.pills")
    }
  }

  // The shared inspector ✕ (matches the habit and calendar panels); re-clicking
  // the task's row in the list collapses it the same way.
  private var hideInspectorButton: some View {
    InspectorCloseButton(accessibilityIdentifier: "task.detail.inspector.close") {
      store.selectedTaskID = nil
    }
  }

  /// The header can render before `TaskDetailView.onAppear`/selection-change
  /// has hydrated the draft for the newly selected task. In that short window,
  /// read from the current task so the inspector never shows stale blank
  /// placeholders like "Title" or the default P2 for a real selected task.
  func taskTitleBinding(for task: LorvexTask) -> Binding<String> {
    Binding {
      store.taskDetailDraftTaskID == task.id ? store.taskDetailTitle : task.title
    } set: { newValue in
      // No draft sync here: hydration happens on appear / selection change. A
      // force-sync inside the setter reset every draft field on each keystroke,
      // forcing a heavy re-render that jumped the caret.
      store.taskDetailTitle = newValue
    }
  }

  func taskPriorityBinding(for task: LorvexTask) -> Binding<LorvexTask.Priority> {
    Binding {
      displayPriority(for: task)
    } set: { newValue in
      store.taskDetailPriority = newValue
    }
  }

  /// Identity-guarded notes binding, mirroring ``taskTitleBinding(for:)``. Until
  /// the draft re-hydrates for the newly selected task, read the task's own notes
  /// rather than the prior task's draft — otherwise the editor briefly shows (and
  /// fast typing could mis-save onto) the previous selection's notes.
  func taskNotesBinding(for task: LorvexTask) -> Binding<String> {
    Binding {
      store.taskDetailDraftTaskID == task.id ? store.taskDetailNotes : task.notes
    } set: { newValue in
      store.taskDetailNotes = newValue
    }
  }

  /// Identity-guarded tags binding, mirroring ``taskTitleBinding(for:)``.
  func taskTagsBinding(for task: LorvexTask) -> Binding<String> {
    Binding {
      store.taskDetailDraftTaskID == task.id
        ? store.taskDetailTagsText : task.tags.joined(separator: ", ")
    } set: { newValue in
      store.taskDetailTagsText = newValue
    }
  }

  func displayPriority(for task: LorvexTask) -> LorvexTask.Priority {
    store.taskDetailDraftTaskID == task.id ? store.taskDetailPriority : task.priority
  }
}

/// A small status fact in the task header — never an editable field.
struct TaskDetailStatusPill: View {
  let text: String
  let systemImage: String
  let tint: Color

  var body: some View {
    LorvexChip(text, systemImage: systemImage, tint: tint)
  }
}
