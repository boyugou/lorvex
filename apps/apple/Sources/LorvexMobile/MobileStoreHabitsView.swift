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
        Label(
          isBatchSelecting
            ? String(localized: "common.done", defaultValue: "Done", table: "Localizable", bundle: MobileL10n.bundle)
            : String(localized: "habits.batch.select", defaultValue: "Select", table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: isBatchSelecting ? "checkmark.circle" : "checklist")
      }
      .disabled(activeHabits.isEmpty || store.habits == nil)
      .lorvexToolbarHoverEffect()
      .accessibilityIdentifier("mobileHabits.batch.toggle")

      Button {
        isShowingCreateHabit = true
      } label: {
        Label(String(localized: "habits.new", defaultValue: "New Habit", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "plus")
      }
      .lorvexToolbarHoverEffect()
      .accessibilityIdentifier("mobileHabits.toolbarCreate")
    }
    .task {
      if store.habits == nil {
        await store.refresh()
      }
    }
    .task(id: habitIDs) {
      if let selectedHabitID = store.selectedHabitID,
        !activeHabits.contains(where: { $0.id == selectedHabitID })
      {
        store.selectHabit(nil)
      }
      pruneBatchSelection()
    }
    .refreshable {
      await store.refreshResettingCloudSyncPacing()
    }
    .searchable(
      text: $searchQuery,
      prompt: String(localized: "habits.search.prompt", defaultValue: "Search habits", table: "Localizable", bundle: MobileL10n.bundle)
    )
    .sheet(isPresented: $isShowingCreateHabit) {
      MobileStoreCreateHabitSheet(store: store, isPresented: $isShowingCreateHabit)
        .lorvexSpatialBackground()
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
      .lorvexSpatialBackground()
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
            complete: { await store.completeHabit($0) },
            reset: { await store.uncompleteHabit($0) },
            searchQuery: searchQuery,
            detailRoute: { .habit($0.id) }
          )
        } else {
          Section(String(localized: "destination.habits", defaultValue: "Habits", table: "Localizable", bundle: MobileL10n.bundle)) {
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
      if let habit = activeHabits.first(where: { $0.id == id }) {
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
      Section(String(localized: "destination.habits", defaultValue: "Habits", table: "Localizable", bundle: MobileL10n.bundle)) {
        if store.habits == nil {
          MobileSkeletonRows(count: 4, showsTrailingDetail: true)
        } else if allActiveHabits.isEmpty {
          ContentUnavailableView(
            String(localized: "habits.empty.no_active", defaultValue: "No Active Habits", table: "Localizable", bundle: MobileL10n.bundle),
            systemImage: "repeat")
        } else if activeHabits.isEmpty {
          ContentUnavailableView.search(text: searchQuery)
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
              }
              .contextMenu {
                habitCompletionAction(habit)
                habitEditAction(habit)
                habitDeleteAction(habit)
              }
              .tag(habit.id)
          }
        }
        // No inline "New Habit" row — the toolbar ＋ is the single add affordance.
      }
    }
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

  private var placeholder: some View {
    ContentUnavailableView {
      Label(String(localized: "habits.detail.empty.title", defaultValue: "Select a Habit", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "repeat")
    } description: {
      Text(String(localized: "habits.detail.empty.description", defaultValue: "Choose a habit to review its progress and update today's completion.", table: "Localizable", bundle: MobileL10n.bundle))
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

  private var habitIDs: [LorvexHabit.ID] {
    activeHabits.map(\.id)
  }

  private var incompleteBatchHabitIDs: [LorvexHabit.ID] {
    activeHabits
      .filter { batchSelectedHabitIDs.contains($0.id) }
      .filter { $0.completionsToday < $0.targetCount }
      .map(\.id)
  }

  private var completedBatchHabitIDs: [LorvexHabit.ID] {
    activeHabits
      .filter { batchSelectedHabitIDs.contains($0.id) }
      .filter { $0.completionsToday > 0 }
      .map(\.id)
  }

  private func toggleBatchSelectionMode() {
    withAnimation(.snappy) {
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
    let liveIDs = Set(activeHabits.map(\.id))
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
    withAnimation(.snappy) {
      isBatchSelecting = false
    }
  }
}
