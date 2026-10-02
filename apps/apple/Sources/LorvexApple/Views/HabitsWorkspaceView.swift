import LorvexCore
import SwiftUI

struct HabitsWorkspaceView: View {
  @Bindable var store: AppStore
  @State private var isShowingCreateHabit = false
  // Non-private so the archived-section view, split into
  // `HabitsWorkspaceArchivedSection.swift`, can drive the same confirmation.
  @State var archivedHabitPendingDeletion: LorvexHabit?

  /// The board's empty state. It carries no create action: the toolbar's add
  /// button is the one way to start a habit.
  private var habitsEmptyState: LorvexEmptyStateModel? {
    if store.habits?.habits.isEmpty == true {
      return LorvexEmptyStateModel(
        title: String(localized: "habits.empty.no_habits_title", defaultValue: "No Habits", table: "Localizable", bundle: LorvexL10n.bundle),
        message: String(
          localized: "habits.empty.no_habits_description",
          defaultValue: "Click ＋ to start a habit you want to build.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: "repeat.circle",
        tint: .accentColor
      )
    }

    return nil
  }

  var body: some View {
    // Group once per render: the header and the grid both read the grouping,
    // so deriving it twice would repeat that work for nothing.
    let habits = store.orderedHabits
    let groups = habitGroups(habits)
    return VStack(spacing: 0) {
      HabitsWorkspaceHeader(stats: stats(habits: habits, onTrack: onTrackByHabitID(habits)))
      Divider()

      ScrollView {
        WorkspaceDashboardLane {
          // Group the board by cadence (Daily / Weekly / Monthly) once more than
          // one cadence is present, so it scans by rhythm; a single-cadence board
          // stays a flat grid with no redundant header.
          if groups.count > 1 {
            VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
              ForEach(groups, id: \.bucket) { group in
                VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
                  habitGroupHeader(group.bucket)
                  habitGrid(group.habits)
                }
              }
            }
            .padding(.horizontal, LorvexDesign.Spacing.l)
            .padding(.vertical, LorvexDesign.Spacing.m)
          } else {
            habitGrid(groups.first?.habits ?? [])
              .padding(.horizontal, LorvexDesign.Spacing.l)
              .padding(.vertical, LorvexDesign.Spacing.m)
          }
        }

        archivedSection
      }
      .overlay {
        // Suppress the "No Habits" empty state while archived habits remain, so
        // the restore section below stays reachable when every habit is archived.
        if let habitsEmptyState, store.archivedHabits.isEmpty {
          LorvexEmptyStatePanel(model: habitsEmptyState)
        }
      }
    }
    .navigationTitle(String(localized: "sidebar.item.habits", defaultValue: "Habits", table: "Localizable", bundle: LorvexL10n.bundle))
    .toolbar {
      ToolbarSpacer(.flexible)

      ToolbarItem(placement: .primaryAction) {
        Button {
          isShowingCreateHabit = true
        } label: {
          Label(
            String(localized: "habits.workspace.create_a11y", defaultValue: "Create Habit", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "plus")
        }
        .help(String(localized: "habits.workspace.create_help", defaultValue: "Create Habit", table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityIdentifier("habits.create")
      }
    }
    .lorvexOpenDestinationActivity(selection: .habits, isActive: store.selection == .habits)
    .task {
      await store.loadAllHabitStats()
      await store.loadArchivedHabits()
    }
    .sheet(isPresented: $isShowingCreateHabit) {
      CreateHabitSheet(store: store, isPresented: $isShowingCreateHabit)
    }
  }

  /// Whether each visible habit meets its current period's plan, keyed by id.
  /// `HabitPeriodProgress.current` parses the habit's completion JSON, so the
  /// header summary and per-cadence stats share this one pass.
  ///
  /// "On track" means meeting the current period's plan (today for daily, this
  /// week / month for weekly / monthly), so the figure is honest across cadences
  /// rather than treating every habit as a daily task.
  private func onTrackByHabitID(_ habits: [LorvexHabit]) -> [LorvexHabit.ID: Bool] {
    Dictionary(uniqueKeysWithValues: habits.map { habit in
      (
        habit.id,
        HabitPeriodProgress.current(
          habit: habit,
          recentCompletions: store.habitStats(for: habit.id)?.recentCompletions ?? [],
          timeZone: store.logicalTimeZone
        ).isComplete
      )
    })
  }

  @ViewBuilder
  private func habitGrid(_ habits: [LorvexHabit]) -> some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: LorvexDesign.Spacing.m)],
      alignment: .leading,
      spacing: LorvexDesign.Spacing.m
    ) {
      ForEach(Array(habits.enumerated()), id: \.element.id) { position, habit in
        HabitMomentumCard(
          habit: habit,
          stats: store.habitStats(for: habit.id),
          isSelected: store.selectedHabitID == habit.id,
          adjust: { delta in Task { await store.adjustHabitCompletion(habit, delta: delta) } },
          reset: { Task { await store.uncompleteHabit(habit) } },
          // Re-clicking the open habit collapses its detail (toggle), matching
          // the inspector's ✕.
          select: { store.selectedHabitID = store.selectedHabitID == habit.id ? nil : habit.id },
          // A habit is edited in its inspector; Edit opens it with the
          // name ready to type.
          edit: {
            store.selectedHabitID = habit.id
            store.habitNameFocusRequest = habit.id
          },
          archive: { Task { await store.setHabitArchived(habit, archived: true) } },
          delete: { Task { await store.deleteHabit(habit) } },
          canMoveUp: position > 0,
          canMoveDown: position < habits.count - 1,
          moveUp: { moveHabitWithinGroup(habit.id, by: -1) },
          moveDown: { moveHabitWithinGroup(habit.id, by: 1) }
        )
      }
    }
  }

  @ViewBuilder
  /// A cadence group's title. It carries no count: the group's cards sit
  /// right under it and never fold away.
  private func habitGroupHeader(_ bucket: HabitCadenceBucket) -> some View {
    Text(bucket.title)
      .font(LorvexDesign.Typography.primaryEmphasis)
      .foregroundStyle(.primary)
      .accessibilityAddTraits(.isHeader)
      .accessibilityIdentifier("habits.group.\(bucket.rawValue)")
  }

  /// Reorder within the habit's own cadence group: swap with its neighbor in the
  /// same bucket. Grouping is by cadence, not stored order, so a global-index
  /// move would read as a no-op when the adjacent habit sits in another group.
  private func moveHabitWithinGroup(_ habitID: LorvexHabit.ID, by delta: Int) {
    let all = store.orderedHabits
    guard let habit = all.first(where: { $0.id == habitID }) else { return }
    let bucket = HabitCadenceBucket(frequencyType: habit.frequencyType)
    let groupIDs = all.filter { HabitCadenceBucket(frequencyType: $0.frequencyType) == bucket }
      .map(\.id)
    guard let posInGroup = groupIDs.firstIndex(of: habitID),
      groupIDs.indices.contains(posInGroup + delta),
      let fromGlobal = all.firstIndex(where: { $0.id == habitID }),
      let neighborGlobal = all.firstIndex(where: { $0.id == groupIDs[posInGroup + delta] })
    else { return }
    let destination = delta > 0 ? neighborGlobal + 1 : neighborGlobal
    Task { await store.moveHabits(fromOffsets: IndexSet(integer: fromGlobal), toOffset: destination) }
  }

  private func stats(habits: [LorvexHabit], onTrack: [LorvexHabit.ID: Bool]) -> HabitsWorkspaceStats {
    // Tally completion per cadence bucket against each habit's own period.
    var counts: [HabitCadenceBucket: (completed: Int, total: Int)] = [:]
    for habit in habits {
      let bucket = HabitCadenceBucket(frequencyType: habit.frequencyType)
      var entry = counts[bucket] ?? (0, 0)
      entry.total += 1
      if onTrack[habit.id] == true { entry.completed += 1 }
      counts[bucket] = entry
    }
    let buckets = HabitCadenceBucket.allCases.compactMap { bucket -> HabitsWorkspaceStats.Bucket? in
      guard let entry = counts[bucket], entry.total > 0 else { return nil }
      return HabitsWorkspaceStats.Bucket(
        cadence: bucket, completed: entry.completed, total: entry.total)
    }
    return HabitsWorkspaceStats(buckets: buckets)
  }

}
