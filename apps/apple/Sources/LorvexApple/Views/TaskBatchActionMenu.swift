import LorvexCore
import SwiftUI

/// The shared Complete / Defer / Move-to-list / Cancel / Reopen actions for a
/// multi-task selection, rendered as the *contents* of a workspace's batch
/// toolbar menu. Every workspace selection menu (Tasks, Calendar,
/// Focus) ends in this identical block; the host supplies the per-surface store
/// calls and the two enablement predicates, and wraps this in its own `Menu`
/// (whose label, `disabled`, and accessibility identifier stay per-surface).
///
/// The move submenu reads the shared list catalog from `store`, so the host
/// only provides the move *handler*.
struct TaskBatchActionMenuContent: View {
  @Bindable var store: AppStore
  let selectionSurface: AppStoreBatchCancelSurface
  /// Whether the selection contains a task that can still be completed /
  /// deferred / cancelled (i.e. not already completed or cancelled).
  let canActOnSelection: Bool
  /// Whether the selection contains a task that can be reopened (completed,
  /// cancelled, or deferred).
  let canReopenSelection: Bool
  /// Whether the selection contains an `open` task that can be parked in the
  /// Someday/Maybe bucket.
  let canMoveSelectionToSomeday: Bool
  let complete: () -> Void
  let deferToTomorrow: () -> Void
  let cancel: () -> Void
  let reopen: () -> Void
  let moveToSomeday: () -> Void
  let move: (LorvexList.ID) -> Void
  /// A list to omit from the move targets — e.g. the list the selection is
  /// already in, when this menu is hosted inside that list's detail. `nil`
  /// (the default) shows every list.
  var excludeListID: LorvexList.ID? = nil

  private var moveTargetLists: [LorvexList] {
    (store.lists?.lists ?? []).filter { excludeListID == nil || $0.id != excludeListID }
  }

  var body: some View {
    Button {
      store.selectAllTasks(on: selectionSurface)
    } label: {
      Label(String(localized: "selection.select_all", defaultValue: "Select All", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "checklist.checked")
    }
    Button {
      store.setTaskSelection([], on: selectionSurface)
    } label: {
      Label(String(localized: "selection.clear", defaultValue: "Clear Selection", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "xmark.circle")
    }
    Divider()

    Button(action: complete) {
      Label(String(localized: "common.complete", defaultValue: "Complete", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "checkmark.circle")
    }
    .disabled(!canActOnSelection)

    Button(action: deferToTomorrow) {
      Label(String(localized: "common.defer", defaultValue: "Defer", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "clock")
    }
    .disabled(!canActOnSelection)

    Button(action: moveToSomeday) {
      Label(
        String(localized: "task.action.move_to_someday", defaultValue: "Move to Someday", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "moon"
      )
    }
    .disabled(!canMoveSelectionToSomeday)

    Menu {
      ForEach(moveTargetLists) { list in
        Button {
          move(list.id)
        } label: {
          Label(list.name, systemImage: list.icon ?? "list.bullet")
        }
      }
    } label: {
      Label(
        String(localized: "sidebar.item.lists", defaultValue: "Lists", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "folder"
      )
    }
    .disabled(moveTargetLists.isEmpty)

    Button(role: .destructive, action: cancel) {
      Label(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "xmark.circle")
    }
    .disabled(!canActOnSelection)

    Button(action: reopen) {
      Label(String(localized: "common.reopen", defaultValue: "Reopen", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "arrow.counterclockwise")
    }
    .disabled(!canReopenSelection)
  }
}
