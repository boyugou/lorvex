import LorvexCore
import SwiftUI

extension TaskDetailView {
  /// Two verbs and an overflow.
  ///
  /// Start and Defer are what a person reaches for while working a day: begin
  /// the task, or move it to another day. Everything else is rare enough that
  /// promoting it would make the panel read as a control surface. Each verb
  /// shows only while it applies, so a finished task keeps just the overflow.
  /// Complete is deliberately absent: the circle beside the title owns it, and
  /// the task's own row sits a few points away with the same affordance.
  func headerActions(task: LorvexTask) -> some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      if store.selectedTaskCanStart || store.selectedTaskCanPause {
        startToggle
      }
      if !task.status.isResolved {
        deferButton
      }
      Spacer(minLength: 0)
      moreActionsMenu(task: task)
    }
    .accessibilityIdentifier("task.detail.header.actions")
  }

  /// Whether the task is started, as a toggle that states where it stands:
  /// "Start" on an open task, and the accent "Started" on a started one,
  /// which pauses it when clicked.
  ///
  /// Tinted rather than filled: a solid accent button is the panel's strongest
  /// signal, and being started is a state, not the thing to do here. The
  /// off-state label is a verb so the control explains itself before it is used.
  private var startToggle: some View {
    let isStarted = store.selectedTaskCanPause
    return Button {
      Task {
        if isStarted {
          await store.pauseSelectedTask()
        } else {
          await store.startSelectedTask()
        }
      }
    } label: {
      HStack(spacing: LorvexDesign.Spacing.xs) {
        Image(systemName: isStarted ? "play.fill" : "play")
          .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
        Text(
          isStarted
            ? String(localized: "task.row.started", defaultValue: "Started", table: "Localizable", bundle: LorvexL10n.bundle)
            : String(localized: "task.action.start", defaultValue: "Start", table: "Localizable", bundle: LorvexL10n.bundle)
        )
        .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
        .fixedSize()
      }
      .foregroundStyle(
        isStarted ? AnyShapeStyle(LorvexDesign.Palette.accent) : AnyShapeStyle(.primary)
      )
      .padding(.horizontal, 10)
      .padding(.vertical, LorvexDesign.Spacing.xs)
      .background {
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
          .fill(
            isStarted
              ? AnyShapeStyle(LorvexDesign.Palette.accent.opacity(0.14))
              : AnyShapeStyle(.quaternary.opacity(0.5)))
      }
      .overlay {
        if isStarted {
          RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
            .stroke(LorvexDesign.Palette.accent.opacity(0.35), lineWidth: 0.5)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(
      isStarted
        ? String(
          localized: "task_detail.actions.pause.help",
          defaultValue: "Pause this task. It stays on its day.",
          table: "Localizable", bundle: LorvexL10n.bundle)
        : String(
          localized: "task_detail.actions.start.help",
          defaultValue: "Start this task. Started tasks lead Today.",
          table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityAddTraits(isStarted ? .isSelected : [])
    .accessibilityIdentifier("task.detail.toggle.started")
  }

  private var deferButton: some View {
    TaskDeferMenu(
      store: store,
      onDefer: { date in Task { await store.deferSelectedTask(until: date) } }
    ) {
      HStack(spacing: LorvexDesign.Spacing.xs) {
        Image(systemName: "clock.arrow.circlepath").font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
        Text(String(localized: "common.defer", defaultValue: "Defer", table: "Localizable", bundle: LorvexL10n.bundle))
          .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
          .fixedSize()
      }
      .foregroundStyle(.primary)
      .padding(.horizontal, 10)
      .padding(.vertical, LorvexDesign.Spacing.xs)
      .background {
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s).fill(.quaternary.opacity(0.5))
      }
      .contentShape(Rectangle())
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .accessibilityIdentifier("task.detail.defer")
  }

  /// Complete / Reopen / Move-to-Open as a ⋯-menu item (the row circle is the
  /// primary path; this keeps them reachable, and covers someday → open which the
  /// circle doesn't handle).
  @ViewBuilder
  private var completionMenuItem: some View {
    if store.selectedTaskIsSomeday {
      Button {
        Task { await store.reopenSelectedTask() }
      } label: {
        Label(
          String(localized: "task.action.move_to_open", defaultValue: "Move to Open", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "arrow.up.circle"
        )
      }
      .accessibilityIdentifier("task.detail.moveToOpen")
    } else if store.selectedTaskCanComplete {
      Button {
        Task { await store.completeSelectedTask(undoManager: undoManager) }
      } label: {
        Label(String(localized: "common.complete", defaultValue: "Complete", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "checkmark.circle")
      }
      .accessibilityIdentifier("task.detail.complete")
    } else if store.selectedTaskCanReopen {
      Button {
        Task { await store.reopenSelectedTask() }
      } label: {
        Label(String(localized: "common.reopen", defaultValue: "Reopen", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "arrow.counterclockwise")
      }
      .accessibilityIdentifier("task.detail.reopen")
    }
  }

  private func moreActionsMenu(task: LorvexTask) -> some View {
    Menu {
      completionMenuItem
      Divider()

      TaskDeferMenu(store: store, onDefer: { date in
        Task { await store.deferSelectedTask(until: date) }
      }) {
        Label(String(localized: "common.defer", defaultValue: "Defer", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "clock.arrow.circlepath")
      }
      .disabled(task.status.isResolved)
      .accessibilityIdentifier("task.detail.defer")

      TaskSnoozeMenu(store: store, onSnooze: { date in
        Task { await store.snoozeSelectedTask(until: date) }
      }) {
        Label(
          String(localized: "task.snooze.title", defaultValue: "Snooze Until", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "eye.slash")
      }
      .disabled(task.status.isResolved)
      .accessibilityIdentifier("task.detail.snooze")

      if store.selectedTaskCanMarkSomeday {
        Button {
          Task { await store.markSelectedTaskSomeday() }
        } label: {
          Label(
            String(localized: "task.action.move_to_someday", defaultValue: "Move to Someday", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "moon"
          )
        }
        .accessibilityIdentifier("task.detail.moveToSomeday")
      }

      if store.canAddTaskToCalendar {
        Button {
          Task { await store.addTaskToCalendar(task) }
        } label: {
          Label(
            String(localized: "task_detail.actions.add_to_calendar", defaultValue: "Add to Calendar", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "calendar.badge.plus"
          )
        }
        .disabled(
          task.status == .cancelled
            || task.status == .completed
            || !store.canAddTaskToCalendar(task)
        )
        .accessibilityIdentifier("task.detail.addToCalendar")
      }

      Divider()

      Button(role: .destructive) {
        store.requestCancel(task, undoManager: undoManager)
      } label: {
        Label(
          String(localized: "task_detail.actions.cancel_task", defaultValue: "Cancel Task", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "xmark.circle"
        )
      }
      .disabled(!store.selectedTaskCanCancel)
      .accessibilityIdentifier("task.detail.cancel")

      Button(role: .destructive) {
        store.requestPermanentDelete(task)
      } label: {
        Label(
          String(localized: "task.permanent_delete.action", defaultValue: "Delete Permanently…", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "trash"
        )
      }
      .accessibilityIdentifier("task.detail.permanentDelete")
    } label: {
      // Only the trigger is icon-only; the menu items keep their titles (setting
      // labelStyle on the Menu itself cascades into the items and hides them).
      Label(String(localized: "common.more", defaultValue: "More", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "ellipsis")
        .labelStyle(.iconOnly)
    }
    .menuStyle(.button)
    .buttonStyle(.bordered)
    .menuIndicator(.hidden)
    .fixedSize(horizontal: true, vertical: false)
    .help(String(localized: "common.more", defaultValue: "More", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityIdentifier("task.detail.more")
  }
}
