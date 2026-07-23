import LorvexCore
import SwiftUI

enum MobileListDetailContentState: Equatable {
  case loading
  case detail(ListDetailSnapshot)
  case unavailable

  static func resolve(
    listID: LorvexList.ID,
    isLoading: Bool,
    selectedDetail: ListDetailSnapshot?,
    failedListDetailID: LorvexList.ID?
  ) -> MobileListDetailContentState {
    if let selectedDetail, selectedDetail.list.id == listID {
      return .detail(selectedDetail)
    }
    if isLoading {
      return .loading
    }
    if failedListDetailID == listID {
      return .unavailable
    }
    return .loading
  }
}

struct MobileStoreListDetailView: View {
  let listID: LorvexList.ID
  @Bindable var store: MobileStore
  @State private var isEditingList = false
  @State private var isConfirmingDelete = false

  var body: some View {
    List {
      switch contentState {
      case .loading:
        MobileListDetailSkeleton()
      case .detail(let detail):
        Section {
          HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
            MobileIconTile(
              icon: detail.list.icon, fallback: "tray.fill",
              tint: Color(lorvexHex: detail.list.color) ?? LorvexDesign.Palette.accent, size: 52)
            VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
              Text(detail.list.name)
                .font(LorvexDesign.Typography.sectionHeader)
              if let description = detail.list.description, !description.isEmpty {
                Text(description)
                  .font(LorvexDesign.Typography.secondaryText)
                  .foregroundStyle(.secondary)
              }
              Text(MobileListDetailFormatters.summary(for: detail))
                .font(LorvexDesign.Typography.tertiaryText)
                .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, LorvexDesign.Spacing.xs)
        }

        Section(
          String(
            localized: "list_detail.section.tasks", defaultValue: "Tasks", table: "Localizable",
            bundle: MobileL10n.bundle)
        ) {
          if detail.tasks.isEmpty {
            MobileEmptyState(
              icon: "checklist",
              title: String(
                localized: "list_detail.empty.no_tasks", defaultValue: "No Tasks",
                table: "Localizable", bundle: MobileL10n.bundle),
              message: String(
                localized: "list_detail.empty.no_tasks.message",
                defaultValue: "Tasks you add to this list show up here.", table: "Localizable",
                bundle: MobileL10n.bundle))
          } else {
            ForEach(detail.tasks) { task in
              MobileActionTaskRow(
                task: task,
                isFocused: store.taskIsFocused(task.id),
                isMutating: store.taskIsMutating(task.id),
                select: { store.selectTask(task.id) },
                toggleFocus: { await store.toggleTaskFocus(task.id, inList: listID) },
                complete: { await store.completeTask(task.id, inList: listID) },
                deferTask: { await store.deferTaskToTomorrow(task.id, inList: listID) }
              )
            }
          }
        }
      case .unavailable:
        MobileEmptyState(
          icon: "tray",
          title: String(
            localized: "list_detail.empty.not_loaded", defaultValue: "List Not Loaded",
            table: "Localizable", bundle: MobileL10n.bundle))
      }
    }
    .navigationTitle(
      store.selectedListDetail?.list.id == listID
        ? store.selectedListDetail?.list.name
          ?? String(
            localized: "list_detail.title", defaultValue: "List", table: "Localizable",
            bundle: MobileL10n.bundle)
        : String(
          localized: "list_detail.title", defaultValue: "List", table: "Localizable",
          bundle: MobileL10n.bundle)
    )
    .task(id: "\(listID)|\(store.listDetailRevision)") {
      await store.loadListDetail(id: listID)
    }
    .refreshable {
      await store.refreshResettingCloudSyncPacing()
      await store.loadListDetail(id: listID)
    }
    .toolbar {
      if let list = store.selectedListDetail?.list, list.id == listID {
        Menu {
          Button {
            store.prepareListDraft(for: list)
            isEditingList = true
          } label: {
            Label(
              String(
                localized: "list_detail.edit_list", defaultValue: "Edit List", table: "Localizable",
                bundle: MobileL10n.bundle), systemImage: "pencil")
          }
          .accessibilityIdentifier("mobileListDetail.edit")

          Button(role: .destructive) {
            isConfirmingDelete = true
          } label: {
            Label(
              String(
                localized: "list_detail.delete_list", defaultValue: "Delete List",
                table: "Localizable", bundle: MobileL10n.bundle), systemImage: "trash")
          }
          .disabled(store.isDeletingList)
          .accessibilityIdentifier("mobileListDetail.delete")
        } label: {
          Label(
            String(
              localized: "list_detail.actions", defaultValue: "List Actions", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "ellipsis.circle")
        }
      }
    }
    .sheet(isPresented: $isEditingList) {
      if let list = store.selectedListDetail?.list {
        MobileStoreEditListSheet(list: list, store: store, isPresented: $isEditingList)
          .lorvexSpatialBackground()
      }
    }
    .confirmationDialog(
      String(
        localized: "list_detail.delete_confirm.title", defaultValue: "Delete this list?",
        table: "Localizable", bundle: MobileL10n.bundle),
      isPresented: $isConfirmingDelete,
      titleVisibility: .visible
    ) {
      if let list = store.selectedListDetail?.list {
        Button(
          String(
            localized: "list_detail.delete_list", defaultValue: "Delete List", table: "Localizable",
            bundle: MobileL10n.bundle), role: .destructive
        ) {
          Task { _ = await store.deleteList(list) }
        }
      }
      Button(
        String(
          localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
          bundle: MobileL10n.bundle), role: .cancel
      ) {}
    } message: {
      Text(
        String(
          localized: "list_detail.delete_confirm.message",
          defaultValue:
            "Only empty lists can be deleted. Lists with assigned tasks must be cleared first.",
          table: "Localizable", bundle: MobileL10n.bundle))
    }
  }

  private var contentState: MobileListDetailContentState {
    MobileListDetailContentState.resolve(
      listID: listID,
      isLoading: store.isLoadingListDetail,
      selectedDetail: store.selectedListDetail,
      failedListDetailID: store.failedListDetailID
    )
  }
}
