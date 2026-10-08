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
  ///
  /// All three wear one face (``headerChip(systemImage:title:isActive:)``), as
  /// tall as each other, so the row reads as one set of controls.
  func headerActions(task: LorvexTask) -> some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      if store.selectedTaskCanStart || store.selectedTaskCanPause {
        startToggle(task: task)
      }
      if !task.status.isResolved {
        deferButton
      }
      Spacer(minLength: 0)
      moreActionsMenu(task: task)
    }
    // Each chip fills the row's height, which is the tallest chip's.
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityIdentifier("task.detail.header.actions")
  }

  /// A header action's face: its symbol and short title (or the symbol alone)
  /// in the primary color on a quiet fill. `isActive` draws the state a
  /// started task's toggle shows instead: accent content on an accent tint
  /// with a hairline edge. Menus wear it through the plain button style,
  /// since a borderless menu would redraw the label in its own colors and
  /// drop the fill.
  private func headerChip(systemImage: String, title: String?, isActive: Bool = false)
    -> some View
  {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      Image(systemName: systemImage)
        .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
        // Beside a title the symbol is decoration; a menu would expose it as a
        // stop of its own. Alone it is the control's only content.
        .accessibilityHidden(title != nil)
      if let title {
        Text(title)
          .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
          .fixedSize()
      }
    }
    .foregroundStyle(isActive ? AnyShapeStyle(LorvexDesign.Palette.accent) : AnyShapeStyle(.primary))
    .padding(.horizontal, 10)
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .frame(maxHeight: .infinity)
    .background {
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
        .fill(
          isActive
            ? AnyShapeStyle(LorvexDesign.Palette.accent.opacity(0.14))
            : AnyShapeStyle(.quaternary.opacity(0.5)))
    }
    .overlay {
      if isActive {
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
          .stroke(LorvexDesign.Palette.accent.opacity(0.35), lineWidth: 0.5)
      }
    }
    .contentShape(Rectangle())
  }

  /// Whether the task is started, as a toggle that states where it stands:
  /// "Start" on an open task, and the accent "Started" on a started one,
  /// which pauses it when clicked.
  ///
  /// Tinted rather than filled: a solid accent button is the panel's strongest
  /// signal, and being started is a state, not the thing to do here. The
  /// off-state label is a verb so the control explains itself before it is used.
  ///
  /// While a task the task waits on is unfinished
  /// (``AppStore/startIsHeldUp(for:)``), Start stays in place but is
  /// unavailable, and its tooltip and accessibility hint say why: the core
  /// would refuse the start, so the control does not offer it.
  private func startToggle(task: LorvexTask) -> some View {
    let isStarted = store.selectedTaskCanPause
    let isUnavailable = !isStarted && store.startIsHeldUp(for: task)
    return Button {
      Task {
        if isStarted {
          await store.pauseSelectedTask()
        } else {
          await store.startSelectedTask()
        }
      }
    } label: {
      headerChip(
        systemImage: isStarted ? "play.fill" : "play",
        title: isStarted
          ? String(localized: "task.row.started", defaultValue: "Started", table: "Localizable", bundle: LorvexL10n.bundle)
          : String(localized: "task.action.start", defaultValue: "Start", table: "Localizable", bundle: LorvexL10n.bundle),
        isActive: isStarted)
    }
    .buttonStyle(.plain)
    .disabled(isUnavailable)
    .help(
      isStarted
        ? String(
          localized: "task_detail.actions.pause.help",
          defaultValue: "Pause this task. It stays on its day.",
          table: "Localizable", bundle: LorvexL10n.bundle)
        : isUnavailable
          ? Self.startHeldUpReason
          : String(
            localized: "task_detail.actions.start.help",
            defaultValue: "Start this task. Started tasks lead Today.",
            table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityHint(isUnavailable ? Self.startHeldUpReason : "")
    .accessibilityAddTraits(isStarted ? .isSelected : [])
    .accessibilityIdentifier("task.detail.toggle.started")
  }

  /// Why Start is unavailable, in the wording the app shows when the core
  /// refuses such a start.
  private static var startHeldUpReason: String {
    UserFacingError.Reason.taskStartBlocked.localizedMessage
  }

  private var deferButton: some View {
    TaskDeferMenu(
      store: store,
      onDefer: { date in Task { await store.deferSelectedTask(until: date) } }
    ) {
      headerChip(
        systemImage: "clock.arrow.circlepath",
        title: String(localized: "common.defer", defaultValue: "Defer", table: "Localizable", bundle: LorvexL10n.bundle))
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize(horizontal: true, vertical: false)
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

      Button {
        openWindow(id: LorvexWindowID.stickyTaskGroupID, value: StickyTaskRef(taskID: task.id))
      } label: {
        Label(
          String(localized: "task_detail.pin_sticky", defaultValue: "Pin as Sticky", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "pin")
      }
      .help(
        String(
          localized: "task_detail.pin_sticky.help",
          defaultValue: "Open this task in a floating sticky window",
          table: "Localizable",
          bundle: LorvexL10n.bundle)
      )
      .accessibilityIdentifier("task.detail.pinSticky")

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
      headerChip(systemImage: "ellipsis", title: nil)
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize(horizontal: true, vertical: false)
    .help(String(localized: "common.more", defaultValue: "More", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityLabel(String(localized: "common.more", defaultValue: "More", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityIdentifier("task.detail.more")
  }
}
