import LorvexCore
import SwiftUI

// MARK: - Focus plan state

/// Gating flags for the Today focus-plan schedule controls.
/// `canProposeSchedule` is true once the plan holds at least one task;
/// `canSaveSchedule` is true once a proposed schedule exists and is awaiting a
/// save.
struct FocusWorkspaceStats: Equatable {
  let canProposeSchedule: Bool
  let canSaveSchedule: Bool

  var hasHeaderActions: Bool {
    canProposeSchedule || canSaveSchedule
  }
}

// MARK: - Schedule controls

/// Propose / Save / Clear controls for the Today focus plan's time-block
/// schedule. Rendered in the Today header when the plan has tasks; the Save
/// button appears only while a proposed schedule is awaiting a save, and the
/// Clear button asks for confirmation through the caller's `clear` closure.
struct TodayScheduleControls: View {
  let stats: FocusWorkspaceStats
  let proposeSchedule: () -> Void
  /// "HH:MM–HH:MM" working window shown in the propose button's tooltip so the
  /// user sees the frame the proposal will fit blocks into.
  var workingHoursText: String?
  let saveSchedule: () -> Void
  let clear: () -> Void

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      if stats.canProposeSchedule {
        Button(action: proposeSchedule) {
          Label(
            String(localized: "focus.workspace.propose_schedule", defaultValue: "Propose Schedule", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "calendar.badge.clock"
          )
        }
        .buttonStyle(.lorvexSecondary)
        .help(proposeHelpText)
        .accessibilityIdentifier("focus.propose.schedule")
      }

      if stats.canSaveSchedule {
        Button(action: saveSchedule) {
          Label(String(localized: "common.save", defaultValue: "Save", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.lorvexPrimary)
        .accessibilityIdentifier("focus.save.schedule")
      }

      if stats.canProposeSchedule {
        Button(role: .destructive, action: clear) {
          Image(systemName: "xmark.circle")
        }
        .buttonStyle(.lorvexNeutral)
        .help(String(localized: "common.clear", defaultValue: "Clear", table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityLabel(String(localized: "common.clear", defaultValue: "Clear", table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityIdentifier("focus.clear")
      }
    }
    .fixedSize(horizontal: true, vertical: false)
  }

  private var proposeHelpText: String {
    guard let workingHoursText else {
      return String(
        localized: "focus.workspace.propose_help",
        defaultValue: "Proposes focus blocks for today's plan.",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    return String(
      format: String(
        localized: "focus.workspace.propose_help_hours",
        defaultValue: "Proposes focus blocks inside your working hours (%@).",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      workingHoursText
    )
  }
}

// MARK: - Selection actions

/// The batch-action menu for a multi-task selection on Today. Adds/removes the
/// selection from the focus plan and exposes the shared complete / defer /
/// cancel / reopen / move actions over `focusWorkspaceSelectedTasks`.
struct FocusSelectionActionMenu: View {
  @Bindable var store: AppStore

  var body: some View {
    Menu {
      Button {
        Task { await store.addFocusWorkspaceSelectionToFocus() }
      } label: {
        Label(String(localized: "task_command.add_to_focus", defaultValue: "Add to Focus", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "scope")
      }
      .disabled(!store.focusWorkspaceSelectedTasks.contains { !store.focusedTaskIDSet.contains($0.id) })

      Button {
        Task { await store.removeFocusWorkspaceSelectionFromFocus() }
      } label: {
        Label(String(localized: "task_command.remove_from_focus", defaultValue: "Remove from Focus", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "scope")
      }
      .disabled(!store.focusWorkspaceSelectedTasks.contains { store.focusedTaskIDSet.contains($0.id) })

      Divider()

      TaskBatchActionMenuContent(
        store: store,
        selectionSurface: .focus,
        canActOnSelection: store.focusWorkspaceSelectedTasks.contains { $0.status.isActive },
        canReopenSelection: store.focusWorkspaceSelectedTasks.contains {
          $0.status.isResolved
        },
        canMoveSelectionToSomeday: store.focusWorkspaceSelectedTasks.contains { $0.status == .open },
        complete: { Task { await store.completeFocusWorkspaceSelection() } },
        deferToTomorrow: { Task { await store.deferFocusWorkspaceSelection() } },
        cancel: { Task { await store.cancelFocusWorkspaceSelection() } },
        reopen: { Task { await store.reopenFocusWorkspaceSelection() } },
        moveToSomeday: { Task { await store.markFocusWorkspaceSelectionSomeday() } },
        move: { listID in Task { await store.moveFocusWorkspaceSelection(toListID: listID) } }
      )
    } label: {
      Label(
        String(
          format: String(
            localized: "focus.selection.count",
            defaultValue: "%lld selected",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ),
          store.focusWorkspaceSelectionCount
        ),
        systemImage: "checklist.checked"
      )
    }
    .buttonStyle(.lorvexNeutral)
    .accessibilityIdentifier("focus.batchTaskSelection")
  }
}
