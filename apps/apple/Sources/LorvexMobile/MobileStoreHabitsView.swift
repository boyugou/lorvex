import LorvexCore
import SwiftUI

/// Full-screen Habits workspace for iPhone/iPad. Wraps the shared habits section
/// into a standalone navigation destination with full create and edit affordances.
@MainActor
public struct MobileStoreHabitsView: View {
  @Bindable var store: MobileStore
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var isShowingCreateHabit = false
  // Non-private so the row-action builders in MobileStoreHabitsView+RowActions
  // can drive them.
  @State var editingHabit: LorvexHabit?
  @State private var searchQuery = ""
  @State var isBatchSelecting = false
  @State private var batchSelectedHabitIDs = Set<LorvexHabit.ID>()
  @State private var isConfirmingBatchDelete = false
  @State var confirmingDeleteHabit: LorvexHabit?

  public init(store: MobileStore) {
    self.store = store
  }

  public var body: some View {
    Group {
      if horizontalSizeClass == .regular {
        regularBody
      } else {
        compactBody
      }
    }
    .navigationTitle(MobileDestination.habits.title)
    .toolbar {
      Button {
        toggleBatchSelectionMode()
      } label: {
        // Words, as Mail and Files write them: a glyph here would repeat the
        // Tasks tab's checklist and read as a jump to Tasks.
        Text(
          isBatchSelecting
            ? String(localized: "common.done", defaultValue: "Done", table: "Localizable", bundle: MobileL10n.bundle)
            : String(localized: "habits.batch.select", defaultValue: "Select", table: "Localizable", bundle: MobileL10n.bundle))
      }
      // "Done" (batch mode) must never disable — it is the only way out; only
      // "Select" is gated on there being habits to select (unfiltered, so a
      // no-match search doesn't hide the entry point).
      .disabled(store.habits == nil || (!isBatchSelecting && allActiveHabits.isEmpty))
      .lorvexToolbarHoverEffect()
      .accessibilityIdentifier("mobileHabits.batch.toggle")

      // Selection mode offers only its own actions, as on the Memory screen.
      if !isBatchSelecting {
        Button {
          isShowingCreateHabit = true
        } label: {
          Label(String(localized: "habits.new", defaultValue: "New Habit", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "plus")
        }
        .lorvexToolbarHoverEffect()
        .accessibilityIdentifier("mobileHabits.toolbarCreate")
      }
    }
    .task {
      if store.habits == nil {
        await store.refresh()
      }
    }
    // Keyed on the UNFILTERED set so it only fires when a habit is actually
    // deleted/archived — not on every search keystroke, which would drop
    // batch selections and clear the open habit just for being filtered out.
    .task(id: allActiveHabitIDs) {
      if let selectedHabitID = store.selectedHabitID,
        !allActiveHabits.contains(where: { $0.id == selectedHabitID })
      {
        store.selectHabit(nil)
      }
      pruneBatchSelection()
      // A habit archived or restored on another device moves between the two
      // lists, so the archived one follows the active set.
      await store.loadArchivedHabits()
    }
    .refreshable {
      await store.refresh()
    }
    .searchable(
      text: $searchQuery,
      prompt: String(localized: "habits.search.prompt", defaultValue: "Search habits", table: "Localizable", bundle: MobileL10n.bundle)
    )
    .sheet(isPresented: $isShowingCreateHabit) {
      MobileStoreCreateHabitSheet(store: store, isPresented: $isShowingCreateHabit)
    }
    .sheet(item: $editingHabit) { habit in
      MobileStoreEditHabitSheet(
        habit: habit,
        store: store,
        isPresented: Binding(
          get: { editingHabit != nil },
          set: { if !$0 { editingHabit = nil } }
        )
      )
    }
    .safeAreaInset(edge: .bottom) {
      if isBatchSelecting {
        MobileHabitBatchActionBar(
          selectedCount: batchSelectedHabitIDs.count,
          canComplete: !incompleteBatchHabitIDs.isEmpty,
          canReset: !completedBatchHabitIDs.isEmpty,
          canDelete: !batchSelectedHabitIDs.isEmpty,
          isMutating: store.isMutatingHabit || store.isDeletingHabit,
          complete: { Task { await performBatchComplete() } },
          reset: { Task { await performBatchReset() } },
          delete: { isConfirmingBatchDelete = true },
          clear: { batchSelectedHabitIDs.removeAll() }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .confirmationDialog(
      String(localized: "habits.batch.delete_confirm.title", defaultValue: "Delete selected habits?", table: "Localizable", bundle: MobileL10n.bundle),
      isPresented: $isConfirmingBatchDelete,
      titleVisibility: .visible
    ) {
      Button(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle), role: .destructive) {
        Task { await performBatchDelete() }
      }
      Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: MobileL10n.bundle), role: .cancel) {}
    } message: {
      Text(String(localized: "habits.row.delete_confirm.message", defaultValue: "This removes its completion history.", table: "Localizable", bundle: MobileL10n.bundle))
    }
    .confirmationDialog(
      confirmingHabitDeleteTitle,
      isPresented: Binding(
        get: { confirmingDeleteHabit != nil },
        set: { if !$0 { confirmingDeleteHabit = nil } }
      ),
      titleVisibility: .visible
    ) {
      if let habit = confirmingDeleteHabit {
        Button(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle), role: .destructive) {
          Task {
            await store.deleteHabit(habit)
            confirmingDeleteHabit = nil
          }
        }
      }
      Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: MobileL10n.bundle), role: .cancel) {}
    } message: {
      Text(String(localized: "habits.row.delete_confirm.message", defaultValue: "This removes its completion history.", table: "Localizable", bundle: MobileL10n.bundle))
    }
    #if DEBUG
      .onAppear {
        if let query = MobileSearchDebugState.takeInitialQuery(for: .habits) {
          searchQuery = query
        }
        if MobileSheetDebugState.take(.newHabit) { isShowingCreateHabit = true }
      }
    #endif
    .accessibilityIdentifier("mobileHabits.root")
  }

  @ViewBuilder
  private var compactBody: some View {
    if isBatchSelecting {
      regularList
    } else {
      List {
        if let habits = store.habits?.habits {
          MobileStoreHabitsSection(
            habits: habits,
            isMutating: store.isMutatingHabit || store.isDeletingHabit,
            editHabit: {
              store.prepareHabitDraft(for: $0)
              editingHabit = $0
            },
            deleteHabit: { await store.deleteHabit($0) },
            archiveHabit: { await store.setHabitArchived($0, archived: true) },
            complete: { await store.completeHabit($0) },
            reset: { await store.uncompleteHabit($0) },
            searchQuery: searchQuery,
            detailRoute: { .habit($0.id) }
          )
          archivedSection
        } else {
          Section {
            MobileSkeletonRows(count: 4, showsTrailingDetail: true)
          }
        }
      }
    }
  }

  private var regularBody: some View {
    MobileAdaptiveListDetail(selection: habitSelection) {
      regularList
    } detail: { id in
      // Resolve from the UNFILTERED active set: an active search filters
      // `activeHabits`, and resolving detail from it would blank the open habit's
      // detail pane to the placeholder just because the user typed a non-matching
      // query — matching how Tasks/Lists/Memory keep their detail during search.
      if let habit = allActiveHabits.first(where: { $0.id == id }) {
        detailPanel(for: habit)
      } else {
        placeholder
      }
    } placeholder: {
      placeholder
    }
  }

  private var regularList: some View {
    List(selection: habitSelection) {
      Section {
        if store.habits == nil {
          MobileSkeletonRows(count: 4, showsTrailingDetail: true)
        } else if allActiveHabits.isEmpty {
          MobileEmptyState(
            icon: "repeat",
            title: String(localized: "habits.empty.no_active", defaultValue: "No Active Habits", table: "Localizable", bundle: MobileL10n.bundle),
            message: String(localized: "habits.empty.no_active.message", defaultValue: "Tap ＋ to start a habit you want to build.", table: "Localizable", bundle: MobileL10n.bundle),
            pointsAtToolbarAdd: true)
        } else if activeHabits.isEmpty {
          MobileEmptyState.search(text: searchQuery)
        } else {
          ForEach(activeHabits) { habit in
            habitCatalogRow(habit)
              .lorvexRowHoverEffect()
              .swipeActions(edge: .leading, allowsFullSwipe: false) {
                habitEditAction(habit)
              }
              .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                habitCompletionAction(habit)
                habitDeleteAction(habit)
                habitArchiveAction(habit)
              }
              .contextMenu {
                habitCompletionAction(habit)
                habitEditAction(habit)
                habitArchiveAction(habit)
                habitDeleteAction(habit)
              }
              .tag(habit.id)
          }
        }
        // No inline "New Habit" row — the toolbar ＋ is the single add affordance.
      }
      if !isBatchSelecting {
        archivedSection
      }
    }
    // Focusable like the Tasks list, so a selected row shows the focus
    // system's quiet fill; the accent fill of a list outside the focus system
    // hides the row's own tint and its trailing control.
    .focusable()
  }

  /// Batch mode wraps the whole row in one toggle button (the ring is passive);
  /// normal mode renders the interactive catalog row (select button + tappable
  /// completion ring as siblings), relying on `List(selection:)` for the tap-to-
  /// select highlight rather than an outer button that would nest the ring.
  @ViewBuilder
  private func habitCatalogRow(_ habit: LorvexHabit) -> some View {
    if isBatchSelecting {
      Button {
        toggleBatchSelection(habit.id)
      } label: {
        HStack(spacing: LorvexDesign.Spacing.m) {
          batchSelectionCheckbox(habit)
          MobileHabitCatalogRow(habit: habit)
        }
      }
      .buttonStyle(.plain)
    } else {
      MobileHabitCatalogRow(
        habit: habit,
        isMutating: store.isMutatingHabit || store.isDeletingHabit,
        onSelect: { store.selectHabit(habit.id) },
        complete: { await store.completeHabit(habit) },
        reset: { await store.uncompleteHabit(habit) }
      )
    }
  }

  private func batchSelectionCheckbox(_ habit: LorvexHabit) -> some View {
    let isSelected = batchSelectedHabitIDs.contains(habit.id)
    return MobileBatchSelectionIndicator(
      isSelected: isSelected,
      accessibilityLabel: isSelected
        ? String(localized: "habits.batch.deselect", defaultValue: "Deselect habit", table: "Localizable", bundle: MobileL10n.bundle)
        : String(localized: "habits.batch.select_habit", defaultValue: "Select habit", table: "Localizable", bundle: MobileL10n.bundle))
  }

  private func detailPanel(for habit: LorvexHabit) -> some View {
    MobileHabitDetailPanel(
      habit: habit,
      detail: store.habitDetail(for: habit.id),
      isMutating: store.isMutatingHabit || store.isDeletingHabit
        || store.isMutatingHabitReminder,
      editHabit: {
        store.prepareHabitDraft(for: habit)
        editingHabit = habit
      },
      deleteHabit: { await store.deleteHabit(habit) },
      archiveHabit: { await store.setHabitArchived(habit, archived: true) },
      complete: { await store.completeHabit(habit) },
      reset: { await store.uncompleteHabit(habit) },
      addReminder: { time in await store.addHabitReminder(habitID: habit.id, time: time) },
      setReminderTime: { policy, time in
        await store.setHabitReminderTime(policy: policy, to: time)
      },
      toggleReminder: { policy in await store.toggleHabitReminderEnabled(policy: policy) },
      removeReminder: { policy in
        await store.removeHabitReminder(habitID: habit.id, policyID: policy.id)
      }
    )
    .task(id: "\(habit.id)|\(store.habitDetailRevision)") {
      await store.loadHabitDetail(id: habit.id)
    }
  }

  /// The archived habits that match the search, below the active catalog.
  private var archivedSection: some View {
    MobileHabitArchivedSection(
      habits: LorvexCatalogSearch.habits(store.archivedHabits, query: searchQuery),
      isMutating: store.isMutatingHabit || store.isDeletingHabit,
      restore: { habit in Task { await store.setHabitArchived(habit, archived: false) } },
      requestDelete: { confirmingDeleteHabit = $0 })
  }

  private var placeholder: some View {
    ContentUnavailableView {
      Label(String(localized: "habits.detail.empty.title", defaultValue: "Select a Habit", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "repeat")
    } description: {
      Text(String(localized: "habits.detail.empty.description", defaultValue: "Choose a habit to see its progress.", table: "Localizable", bundle: MobileL10n.bundle))
    }
  }

  private var habitSelection: Binding<LorvexHabit.ID?> {
    Binding(
      get: { store.selectedHabitID },
      set: { store.selectHabit($0) }
    )
  }

  private var allActiveHabits: [LorvexHabit] {
    (store.habits?.habits ?? []).filter { !$0.archived }
  }

  private var activeHabits: [LorvexHabit] {
    LorvexCatalogSearch.habits(allActiveHabits, query: searchQuery)
  }

  private var confirmingHabitDeleteTitle: String {
    guard let habit = confirmingDeleteHabit else {
      return String(localized: "habits.row.delete_confirm.title", defaultValue: "Delete habit “%@”?", table: "Localizable", bundle: MobileL10n.bundle)
    }
    return String(
      format: String(localized: "habits.row.delete_confirm.title", defaultValue: "Delete habit “%@”?", table: "Localizable", bundle: MobileL10n.bundle),
      habit.name)
  }

  private var allActiveHabitIDs: [LorvexHabit.ID] {
    allActiveHabits.map(\.id)
  }

  // Batch actions operate on the full selection, not just the search-visible
  // subset — the selection persists across a search used to find more habits.
  private var incompleteBatchHabitIDs: [LorvexHabit.ID] {
    allActiveHabits
      .filter { batchSelectedHabitIDs.contains($0.id) }
      .filter { $0.completionsToday < $0.targetCount }
      .map(\.id)
  }

  private var completedBatchHabitIDs: [LorvexHabit.ID] {
    allActiveHabits
      .filter { batchSelectedHabitIDs.contains($0.id) }
      .filter { $0.completionsToday > 0 }
      .map(\.id)
  }

  private func toggleBatchSelectionMode() {
    lorvexAnimated(.snappy) {
      isBatchSelecting.toggle()
      if !isBatchSelecting {
        batchSelectedHabitIDs.removeAll()
      }
    }
  }

  private func toggleBatchSelection(_ habitID: LorvexHabit.ID) {
    if batchSelectedHabitIDs.contains(habitID) {
      batchSelectedHabitIDs.remove(habitID)
    } else {
      batchSelectedHabitIDs.insert(habitID)
    }
  }

  private func pruneBatchSelection() {
    // Intersect with the UNFILTERED set: a search must never drop a selection,
    // only a genuinely removed/archived habit should.
    let liveIDs = Set(allActiveHabits.map(\.id))
    batchSelectedHabitIDs = batchSelectedHabitIDs.intersection(liveIDs)
  }

  private func performBatchComplete() async {
    let ids = incompleteBatchHabitIDs
    guard await store.completeHabits(ids) else { return }
    batchSelectedHabitIDs.subtract(ids)
  }

  private func performBatchReset() async {
    let ids = completedBatchHabitIDs
    guard await store.uncompleteHabits(ids) else { return }
    batchSelectedHabitIDs.subtract(ids)
  }

  private func performBatchDelete() async {
    let ids = Array(batchSelectedHabitIDs)
    guard await store.deleteHabits(ids) else { return }
    batchSelectedHabitIDs.removeAll()
    lorvexAnimated(.snappy) {
      isBatchSelecting = false
    }
  }
}
