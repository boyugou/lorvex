import LorvexCore
import SwiftUI

/// The scoped task list — the drill-in from the Tasks home. Shows the tasks for
/// one ``MobileTasksScope`` (a smart collection or a list), querying the core
/// task corpus directly rather than reusing the small Today snapshot. Scoped to
/// a list, it is that list's only screen, whichever way it opened, and
/// ``MobileListScopeChrome`` adds the list's description and its Edit / Delete
/// menu.
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
  /// A reload requested while a `loadMore` (or another `load`) was in flight,
  /// deferred so it can't write `page` concurrently. Drained when the in-flight
  /// load settles, so a mutation/inbound reload issued while the next page loads
  /// is never silently dropped, leaving resolved tasks or stale-query rows on
  /// screen.
  @State var pendingReload = false
  /// True while the footer below the last loaded row is on screen. A settled
  /// load reads it to fetch the next page without waiting for another scroll.
  @State var isLoadedEndVisible = false
  @State var selectedTaskID: LorvexTask.ID?
  /// The row an arrow key or Return just selected, which the list scrolls
  /// into view. A tap selects without setting it, so the row the person
  /// touched stays where it is.
  @State var keyboardScrollTarget: LorvexTask.ID?
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
        // Words, as Mail and Files write them: a glyph here would repeat the
        // Tasks tab's checklist and read as a jump to Tasks.
        Text(
          isBatchSelecting
            ? String(
              localized: "common.done", defaultValue: "Done", table: "Localizable",
              bundle: MobileL10n.bundle)
            : String(
              localized: "tasks.batch.select", defaultValue: "Select", table: "Localizable",
              bundle: MobileL10n.bundle))
      }
      // Never disable while batch selecting, or an emptied page would trap the
      // user in selection mode with no way back out.
      .disabled(!isBatchSelecting && (page.tasks.isEmpty || isLoading))
      .lorvexToolbarHoverEffect()
      .accessibilityIdentifier("mobileTasks.batch.toggle")

      // No manual refresh button — pull-to-refresh (.refreshable) + live sync
      // already keep the list current; a refresh button reads as a stale idiom.
      // No ＋ either: the tab bar's round ＋ raises capture on every tab.
    }
    .modifier(
      MobileListScopeChrome(store: store, listID: scope.listID, isBatchSelecting: isBatchSelecting))
    .refreshable {
      await store.refresh()
      await load()
    }
    .searchable(
      text: $query,
      prompt: String(
        localized: "tasks.search.prompt", defaultValue: "Search tasks", table: "Localizable",
        bundle: MobileL10n.bundle)
    )
    .task(id: loadKey) {
      guard await LorvexSearchDebounce.shouldSearch(query) else { return }
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
        localized: "tasks.batch.title.count",
        defaultValue: "\(batchSelectedTaskIDs.count) selected",
        table: "Localizable", bundle: MobileL10n.bundle)
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
            defaultValue: "Choose a task to see its details.",
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
            let timeLabels = store.todayTimeLabels
            ForEach(page.tasks) { task in
              taskRow(task, timeLabel: timeLabels[task.id])
                .id(task.id)
            }
          }
        } footer: {
          // Reaching the end of the loaded rows fetches the next page, so the
          // list scrolls on without a Load More button.
          if page.nextOffset != nil {
            ProgressView()
              .frame(maxWidth: .infinity)
              .accessibilityLabel(
                String(
                  localized: "tasks.results.loading_more", defaultValue: "Loading more tasks",
                  table: "Localizable", bundle: MobileL10n.bundle)
              )
              .accessibilityIdentifier("mobileTasks.loadingMore")
              .onAppear {
                isLoadedEndVisible = true
                loadMoreIfAtLoadedEnd()
              }
              .onDisappear { isLoadedEndVisible = false }
          }
        }
      }
      .focusable()
      .focused($isTaskListFocused)
      .onAppear(perform: seedTaskListFocusIfNeeded)
      .onChange(of: keyboardScrollTarget) { _, taskID in
        guard let taskID else { return }
        keyboardScrollTarget = nil
        // The least scroll that shows the row, as the Mac list moves with the
        // keyboard.
        withAnimation(.snappy(duration: 0.16)) { proxy.scrollTo(taskID, anchor: nil) }
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
  private func taskRow(_ task: LorvexTask, timeLabel: String?) -> some View {
    if horizontalSizeClass == .regular || isBatchSelecting {
      MobileTaskWorkspaceSelectableRow(
        task: task,
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
        actions: store.rowActions(for: task.id) { await load() },
        timeLabel: timeLabel,
        isBlocked: page.blockedTaskIDs.contains(task.id)
      )
      .tag(task.id)
    } else {
      MobileActionTaskRow(
        task: task,
        isBlocked: page.blockedTaskIDs.contains(task.id),
        isMutating: store.taskIsMutating(task.id),
        actions: store.rowActions(for: task.id) { await load() },
        timeLabel: timeLabel
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
        systemImage: "clock", tint: LorvexDesign.Palette.dueSoon,
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
