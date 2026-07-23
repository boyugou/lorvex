import LorvexCore
import SwiftUI

extension TaskDetailView {
  func headerActions(task: LorvexTask, draftHasChanges: Bool, canSave: Bool) -> some View {
    TaskDetailActionRail {
      // No prominent Complete/Reopen button: the selected task's row sits right
      // beside this inspector with an always-visible tap-to-complete circle, so a
      // second Complete here is pure duplication. Complete / Reopen / Move-to-Open
      // live in the ⋯ menu instead (the someday → open case isn't on the circle).
      ViewThatFits(in: .horizontal) {
        HStack(spacing: LorvexDesign.Spacing.s) {
          if draftHasChanges {
            saveButton(canSave: canSave)
          }
          focusButton
          moreActionsMenu(task: task)
        }

        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
          if draftHasChanges {
            saveButton(canSave: canSave)
          }
          HStack(spacing: LorvexDesign.Spacing.s) {
            focusButton
            moreActionsMenu(task: task)
          }
        }
      }
    }
    .accessibilityIdentifier("task.detail.header.actions")
  }

  private func saveButton(canSave: Bool) -> some View {
    Button {
      Task { await store.saveSelectedTaskDraft() }
    } label: {
      Label(String(localized: "common.save", defaultValue: "Save", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "square.and.arrow.down")
    }
    .buttonStyle(.lorvexPrimary)
    .fixedSize(horizontal: true, vertical: false)
    .disabled(!canSave)
    .accessibilityIdentifier("task.detail.save")
  }

  private var focusButton: some View {
    Button {
      Task { await store.toggleSelectedTaskFocus() }
    } label: {
      Label(
        store.selectedTaskIsFocused
          ? String(localized: "task_detail.actions.unfocus", defaultValue: "Unfocus", table: "Localizable", bundle: LorvexL10n.bundle)
          : String(localized: "task_detail.actions.focus", defaultValue: "Focus", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: store.selectedTaskIsFocused ? "minus.circle" : "scope"
      )
    }
    .buttonStyle(.lorvexSecondary)
    .fixedSize(horizontal: true, vertical: false)
    .accessibilityIdentifier("task.detail.toggle.focus")
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

      if store.selectedTaskCanStart {
        Button {
          Task { await store.startSelectedTask() }
        } label: {
          Label(
            String(localized: "task.action.start", defaultValue: "Start", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "play.circle")
        }
        .accessibilityIdentifier("task.detail.start")
      }
      if store.selectedTaskCanMarkNotStarted {
        Button {
          Task { await store.markSelectedTaskNotStarted() }
        } label: {
          Label(
            String(
              localized: "task.action.mark_not_started", defaultValue: "Mark as Not Started",
              table: "Localizable",
              bundle: LorvexL10n.bundle),
            systemImage: "pause.circle")
        }
        .accessibilityIdentifier("task.detail.markNotStarted")
      }

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
    .buttonStyle(.lorvexNeutral)
    .menuIndicator(.hidden)
    .fixedSize(horizontal: true, vertical: false)
    .help(String(localized: "common.more", defaultValue: "More", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityIdentifier("task.detail.more")
  }
}

private struct TaskDetailActionRail<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .controlSize(.small)
      .buttonBorderShape(.roundedRectangle(radius: LorvexDesign.Radius.s))
      .labelStyle(.titleAndIcon)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, LorvexDesign.Spacing.xs)
      .accessibilityIdentifier("task.detail.actionRail")
  }
}
