import LorvexCore
import SwiftUI

/// What a list's own screen adds to the scoped Tasks workspace: the list's
/// description under its title, and a List Actions menu with Edit List and
/// Delete List. A list has this one screen however it opens — from the Tasks
/// home, a deep link, Handoff, or right after it is created.
///
/// Delete List appears for every list but the Inbox, which the core never
/// deletes. The core also refuses a list that still holds tasks, so for one the
/// item stays disabled and says why, and an empty list asks once before it
/// goes; the screen then closes because deleting a list pops its routes. While
/// the workspace is batch selecting, the menu steps aside so the toolbar holds
/// only the selection's Done. A scope that is not a list (`listID == nil`)
/// passes through unchanged.
struct MobileListScopeChrome: ViewModifier {
  @Bindable var store: MobileStore
  let listID: LorvexList.ID?
  let isBatchSelecting: Bool
  @State private var editingList: LorvexList?
  @State private var listAwaitingDelete: LorvexList?

  private var list: LorvexList? {
    guard let listID else { return nil }
    return store.lists?.lists.first { $0.id == listID }
  }

  func body(content: Content) -> some View {
    content
      .navigationSubtitle(list?.description ?? "")
      .toolbar {
        if let list, !isBatchSelecting {
          ToolbarItem(placement: .primaryAction) {
            actionsMenu(list)
          }
        }
      }
      .sheet(item: $editingList) { list in
        MobileStoreEditListSheet(
          list: list,
          store: store,
          isPresented: Binding(get: { editingList != nil }, set: { if !$0 { editingList = nil } })
        )
      }
  }

  private func actionsMenu(_ list: LorvexList) -> some View {
    Menu {
      Button {
        store.prepareListDraft(for: list)
        editingList = list
      } label: {
        Label(
          String(
            localized: "list_detail.edit_list", defaultValue: "Edit List", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "pencil")
      }
      .accessibilityIdentifier("mobileTasks.list.edit")

      if !list.isInbox {
        Button(role: .destructive) {
          listAwaitingDelete = list
        } label: {
          Label {
            Text(
              String(
                localized: "list_detail.delete_list", defaultValue: "Delete List",
                table: "Localizable", bundle: MobileL10n.bundle))
            if list.totalCount > 0 {
              Text(
                String(
                  localized: "list_detail.delete_list.needs_empty",
                  defaultValue: "Only an empty list can be deleted",
                  table: "Localizable", bundle: MobileL10n.bundle))
            }
          } icon: {
            Image(systemName: "trash")
          }
        }
        .disabled(list.totalCount > 0 || store.isDeletingList)
        .accessibilityIdentifier("mobileTasks.list.delete")
      }
    } label: {
      Label(
        String(
          localized: "list_detail.actions", defaultValue: "List Actions", table: "Localizable",
          bundle: MobileL10n.bundle), systemImage: "ellipsis")
    }
    .lorvexToolbarHoverEffect()
    .accessibilityIdentifier("mobileTasks.list.actions")
    // The confirmation hangs off the menu that raised it, so on the iPhone it
    // points at the ellipsis button rather than opening away from it.
    .mobileDeleteConfirmation(
      of: list, pending: $listAwaitingDelete,
      title: String(
        localized: "list_detail.delete_confirm.title", defaultValue: "Delete this list?",
        table: "Localizable", bundle: MobileL10n.bundle),
      confirmTitle: String(
        localized: "list_detail.delete_list", defaultValue: "Delete List", table: "Localizable",
        bundle: MobileL10n.bundle)
    ) { list in
      Task { _ = await store.deleteList(list) }
    }
  }
}
