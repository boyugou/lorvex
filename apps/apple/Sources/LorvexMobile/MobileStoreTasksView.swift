import LorvexCore
import SwiftUI

/// The scoped task list — the drill-in from the Tasks home. Shows the tasks for
/// one ``MobileTasksScope`` (a smart collection or a list), querying the core
/// task corpus directly rather than reusing the small Today snapshot.
@MainActor
public struct MobileStoreTasksView: View {
  @Bindable var store: MobileStore
  let scope: MobileTasksScope
  let scopeTitle: String
  @Environment(\.horizontalSizeClass) var horizontalSizeClass
  @State var query = ""
  @State var page = MobileTaskWorkspacePage.empty
  @State var isLoading = false
  @State var isLoadingMore = false
  @State var selectedTaskID: LorvexTask.ID?
  @State var isBatchSelecting = false
  @State var batchSelectedTaskIDs = Set<LorvexTask.ID>()
  @FocusState var isTaskListFocused: Bool

  public init(
    store: MobileStore,
    scope: MobileTasksScope = .all,
    scopeTitle: String = MobileDestination.tasks.title
  ) {
    self.store = store
    self.scope = scope
    self.scopeTitle = scopeTitle
  }

  public var body: some View {
    Group {
      if horizontalSizeClass == .regular {
        regularBody
      } else {
        compactBody
      }
    }
    // While selecting, the title carries the live count (Photos/Mail idiom),
    // so the bottom bar can stay a single uncluttered row of actions; otherwise
    // it names the scope (the collection or list this drill-in is showing).
    .navigationTitle(isBatchSelecting ? batchSelectionTitle : scopeTitle)
    // Replace the tab bar with the contextual action bar during selection
    // (Photos idiom) rather than stacking two bars at the bottom. `.tabBar`
    // placement is iOS-only (LorvexMobile also compiles on the macOS host).
    #if os(iOS)
      .toolbar(isBatchSelecting ? .hidden : .visible, for: .tabBar)
    #endif
    .toolbar {
      Button {
        toggleBatchSelectionMode()
      } label: {
        Label(
          isBatchSelecting
            ? String(
              localized: "common.done", defaultValue: "Done", table: "Localizable",
              bundle: MobileL10n.bundle)
            : String(
              localized: "tasks.batch.select", defaultValue: "Select", table: "Localizable",
              bundle: MobileL10n.bundle),
          systemImage: isBatchSelecting ? "checkmark.circle" : "checklist")
      }
      // Never disable while batch selecting, or an emptied page would trap the
      // user in selection mode with no way back out.
      .disabled(!isBatchSelecting && (page.tasks.isEmpty || isLoading))
      .lorvexToolbarHoverEffect()
      .accessibilityIdentifier("mobileTasks.batch.toggle")

      // No manual refresh button — pull-to-refresh (.refreshable) + live sync
      // already keep the list current; a refresh button reads as a stale idiom.
      // The add affordance steps aside during selection (nothing to add then).
      if !isBatchSelecting {
        Button {
          store.isPresentingCapture = true
        } label: {
          Label(
            String(
              localized: "capture.sheet.title", defaultValue: "Capture", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "plus")
        }
        .lorvexToolbarHoverEffect()
        .accessibilityIdentifier("mobileTasks.new")
      }
    }
    .refreshable {
      await store.refreshResettingCloudSyncPacing()
      await load()
    }
    .searchable(
      text: $query,
      prompt: String(
        localized: "tasks.search.prompt", defaultValue: "Search tasks", table: "Localizable",
        bundle: MobileL10n.bundle)
    )
    .task(id: loadKey) {
      await debounceSearchIfNeeded()
      guard !Task.isCancelled else { return }
      await load()
      #if DEBUG
        if MobileStore.debugAutoBatchSelectTasks, !isBatchSelecting, !page.tasks.isEmpty {
          isBatchSelecting = true
          batchSelectedTaskIDs = Set(page.tasks.prefix(2).map(\.id))
        }
      #endif
    }
    // The Tasks home (this view's stack root) owns the MobileRoute destination,
    // so task-detail pushes from here resolve there — declaring it again would
    // collide.
    .safeAreaInset(edge: .bottom) {
      if isBatchSelecting {
        MobileTaskBatchActionBar(
          canCompleteOrDefer: !batchActionIDs(done: false).isEmpty,
          canReopen: !batchActionIDs(done: true).isEmpty,
          isMutating: store.isMutatingTask,
          complete: { Task { await performBatchComplete() } },
          deferTask: { Task { await performBatchDefer() } },
          reopen: { Task { await performBatchReopen() } }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .accessibilityIdentifier("mobileTasks.root")
  }

  /// Title shown while batch selecting — the live count stands in for the
  /// "Tasks" title (Photos/Mail idiom), keeping the count out of the action bar.
  private var batchSelectionTitle: String {
    batchSelectedTaskIDs.isEmpty
      ? String(
        localized: "tasks.batch.title.empty", defaultValue: "Select Tasks", table: "Localizable",
        bundle: MobileL10n.bundle)
      : String(
        format: String(
          localized: "tasks.batch.title.count", defaultValue: "%lld selected", table: "Localizable",
          bundle: MobileL10n.bundle),
        batchSelectedTaskIDs.count)
  }

  /// Selection binding for the regular-width path. Reads/writes
  /// `store.selectedTaskID` (settable only via `store.selectTask`) so the
  /// selection survives the shell flipping `horizontalSizeClass` on rotation /
  /// multitasking, and so the same value drives both the side-by-side detail
  /// and the narrow navigation-stack push.
  private var regularSelection: Binding<LorvexTask.ID?> {
    Binding(
      get: { store.selectedTaskID },
      set: { store.selectTask($0) }
    )
  }

  private var regularBody: some View {
    MobileAdaptiveListDetail(selection: regularSelection) {
      taskList
    } detail: { id in
      MobileStoreRouteView(route: .task(id), store: store)
    } placeholder: {
      ContentUnavailableView {
        Label(
          String(
            localized: "tasks.detail.empty.title", defaultValue: "Select a Task",
            table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: "sidebar.right")
      } description: {
        Text(
          String(
            localized: "tasks.detail.empty.message",
            defaultValue: "Choose a task from the workspace list to inspect details and actions.",
            table: "Localizable", bundle: MobileL10n.bundle))
      }
    }
  }

  private var compactBody: some View {
    taskList
  }

  private var taskList: some View {
    ScrollViewReader { proxy in
      List(selection: horizontalSizeClass == .regular ? regularSelection : $selectedTaskID) {
        Section {
          if isLoading && page.tasks.isEmpty {
            MobileSkeletonRows(count: 5)
          } else if page.tasks.isEmpty {
            MobileStoreTaskEmptyState(
              store: store,
              title: scope.baseStatus.emptyTitle,
              message: scope.baseStatus.emptyMessage
            )
          } else {
            ForEach(page.tasks) { task in
              taskRow(task)
                .id(task.id)
            }
          }
        } header: {
          Text(sectionTitle)
        } footer: {
          if let nextOffset = page.nextOffset {
            Button {
              Task { await loadMore(offset: nextOffset) }
            } label: {
              if isLoadingMore {
                ProgressView()
              } else {
                Label(
                  String(
                    localized: "tasks.results.load_more", defaultValue: "Load More",
                    table: "Localizable", bundle: MobileL10n.bundle),
                  systemImage: "chevron.down.circle")
              }
            }
            .disabled(isLoading || isLoadingMore)
            .accessibilityIdentifier("mobileTasks.loadMore")
          }
        }
      }
      .focusable()
      .focused($isTaskListFocused)
      .onAppear(perform: seedTaskListFocusIfNeeded)
      .onChange(of: keyboardSelectedTaskID) { _, taskID in
        guard let taskID else { return }
        withAnimation { proxy.scrollTo(taskID, anchor: .center) }
      }
      .onKeyPress(.upArrow) {
        moveTaskSelection(by: -1) ? .handled : .ignored
      }
      .onKeyPress(.downArrow) {
        moveTaskSelection(by: 1) ? .handled : .ignored
      }
      .onKeyPress(.return) {
        openSelectedTaskFromKeyboard() ? .handled : .ignored
      }
    }
  }

  @ViewBuilder
  private func taskRow(_ task: LorvexTask) -> some View {
    if horizontalSizeClass == .regular || isBatchSelecting {
      MobileTaskWorkspaceSelectableRow(
        task: task,
        isFocused: store.taskIsFocused(task.id),
        isMutating: store.taskIsMutating(task.id),
        select: {
          if isBatchSelecting {
            toggleBatchSelection(task.id)
          } else {
            store.selectTask(task.id)
          }
        },
        isBatchSelecting: isBatchSelecting,
        isBatchSelected: batchSelectedTaskIDs.contains(task.id),
        toggleFocus: { await store.toggleTaskFocus(task.id) },
        complete: { await mutateAndReload { await store.completeTask(task.id) } },
        deferTask: { await mutateAndReload { await store.deferTaskToTomorrow(task.id) } }
      )
      .tag(task.id)
    } else {
      MobileActionTaskRow(
        task: task,
        isFocused: store.taskIsFocused(task.id),
        isMutating: store.taskIsMutating(task.id),
        select: { store.selectTask(task.id) },
        toggleFocus: { await store.toggleTaskFocus(task.id) },
        complete: { await mutateAndReload { await store.completeTask(task.id) } },
        deferTask: { await mutateAndReload { await store.deferTaskToTomorrow(task.id) } }
      )
    }
  }

}

/// A single, light contextual action row (Photos-style) shown while batch
/// selecting. Each action is an equal-width icon-over-label button that tints
/// when enabled and dims when not; the selection count lives in the nav title.
private struct MobileTaskBatchActionBar: View {
  let canCompleteOrDefer: Bool
  let canReopen: Bool
  let isMutating: Bool
  let complete: () -> Void
  let deferTask: () -> Void
  let reopen: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      action(
        label: LocalizedStringResource(
          "action.complete", defaultValue: "Complete",
          table: "Localizable", bundle: MobileL10n.bundle),
        identifier: "complete",
        systemImage: "checkmark.circle.fill", tint: LorvexDesign.Palette.done,
        enabled: canCompleteOrDefer, action: complete)
      action(
        label: LocalizedStringResource(
          "action.defer", defaultValue: "Defer",
          table: "Localizable", bundle: MobileL10n.bundle),
        identifier: "defer",
        systemImage: "clock", tint: .orange,
        enabled: canCompleteOrDefer, action: deferTask)
      action(
        label: LocalizedStringResource(
          "action.reopen", defaultValue: "Reopen",
          table: "Localizable", bundle: MobileL10n.bundle),
        identifier: "reopen",
        systemImage: "arrow.uturn.backward", tint: .accentColor,
        enabled: canReopen, action: reopen)
    }
    .padding(.top, LorvexDesign.Spacing.xs)
    .background(.bar)
    .overlay(alignment: .top) { Divider() }
    .accessibilityIdentifier("mobileTasks.batchActionBar")
  }

  private func action(
    label: LocalizedStringResource,
    identifier: String,
    systemImage: String,
    tint: Color,
    enabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: systemImage)
          .font(.title3)
        Text(label)
          .font(.caption2)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, LorvexDesign.Spacing.xs)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(enabled && !isMutating ? tint : Color.secondary.opacity(0.6))
    .disabled(!enabled || isMutating)
    .accessibilityIdentifier("mobileTasks.batch.\(identifier)")
  }
}
