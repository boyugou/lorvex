import LorvexCore
import SwiftUI

struct HabitsWorkspaceView: View {
  @Bindable var store: AppStore
  @State private var isShowingCreateHabit = false
  @State private var editingHabit: LorvexHabit?
  // Non-private so the archived-section view, split into
  // `HabitsWorkspaceArchivedSection.swift`, can drive the same confirmation.
  @State var archivedHabitPendingDeletion: LorvexHabit?

  private var habitsEmptyState: LorvexEmptyStateModel? {
    if store.hasActiveSearch && store.filteredHabits.isEmpty {
      return LorvexEmptyStateModel(
        title: String(localized: "habits.empty.search_title", defaultValue: "No Habit Results", table: "Localizable", bundle: LorvexL10n.bundle),
        message: String(
          localized: "habits.empty.search_description",
          defaultValue: "No tracked habit matches the current search.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: "magnifyingglass",
        tint: .secondary,
        chips: [
          LorvexEmptyStateChip(
            title: store.searchText,
            systemImage: "text.magnifyingglass",
            tint: .accentColor
          )
        ],
        action: LorvexEmptyStateAction(
          title: String(localized: "common.clear_search", defaultValue: "Clear Search", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "xmark.circle"
        ) {
          store.searchText = ""
        }
      )
    }

    if store.habits?.habits.isEmpty == true {
      return LorvexEmptyStateModel(
        title: String(localized: "habits.empty.no_habits_title", defaultValue: "No Habits", table: "Localizable", bundle: LorvexL10n.bundle),
        message: String(
          localized: "habits.empty.no_habits_description",
          defaultValue: "Habits you track will appear here.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: "repeat.circle",
        tint: .accentColor,
        chips: [],
        action: LorvexEmptyStateAction(
          title: String(localized: "habits.create", defaultValue: "Create Habit", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "plus",
          style: .primary
        ) {
          isShowingCreateHabit = true
        }
      )
    }

    return nil
  }

  var body: some View {
    // Group once per render. The grouping derives from `store.filteredHabits`
    // (a search filter + ordered sort), so deriving it twice — once for the
    // header flag, once for the ForEach — repeated that work for nothing.
    let habits = store.filteredHabits
    let groups = habitGroups(habits)
    // Resolve period progress once: it parses each habit's completion JSON, and
    // both the header summary ("on track" count) and the per-cadence stats need
    // it, so computing it twice would re-parse every habit for nothing.
    let onTrack = onTrackByHabitID(habits)
    return VStack(spacing: 0) {
      HabitsWorkspaceHeader(
        summary: summary(habits: habits, onTrack: onTrack),
        stats: stats(habits: habits, onTrack: onTrack),
        create: { isShowingCreateHabit = true }
      )
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
                  habitGroupHeader(group.bucket, count: group.habits.count)
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

        if !store.archivedHabits.isEmpty {
          archivedSection
        }
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
    .lorvexOpenDestinationActivity(selection: .habits, isActive: store.selection == .habits)
    .task {
      await store.loadAllHabitStats()
      await store.loadArchivedHabits()
    }
    .sheet(isPresented: $isShowingCreateHabit) {
      CreateHabitSheet(store: store, isPresented: $isShowingCreateHabit)
    }
    .sheet(item: $editingHabit) { habit in
      EditHabitSheet(
        habit: habit,
        store: store,
        isPresented: Binding(
          get: { editingHabit != nil },
          set: { if !$0 { editingHabit = nil } }
        )
      )
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
          recentCompletions: store.habitStats(for: habit.id)?.recentCompletions ?? []
        ).isComplete
      )
    })
  }

  private func summary(habits: [LorvexHabit], onTrack: [LorvexHabit.ID: Bool]) -> String {
    let count = habits.count
    // With no habits the empty state carries the messaging.
    if count == 0 && !store.hasActiveSearch {
      return String(
        localized: "habits.summary.none", defaultValue: "Build a routine by tracking a habit.",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    if store.hasActiveSearch {
      return String(
        localized: "habits.summary.search_count",
        defaultValue: "\(count) habits matching the current search.",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    let onTrackCount = habits.filter { onTrack[$0.id] == true }.count
    return String(
      format: String(
        localized: "habits.summary.on_track", defaultValue: "%1$lld of %2$lld habits on track.",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      Int64(onTrackCount), Int64(count))
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
          edit: {
            store.prepareHabitDraft(for: habit)
            editingHabit = habit
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
  private func habitGroupHeader(_ bucket: HabitCadenceBucket, count: Int) -> some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Text(bucket.title)
        .font(LorvexDesign.Typography.primaryEmphasis)
        .foregroundStyle(.primary)
      Text("\(count)")
        .font(LorvexDesign.Typography.tertiaryText.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(.quaternary.opacity(0.5), in: Capsule())
      Spacer(minLength: 0)
    }
    .accessibilityIdentifier("habits.group.\(bucket.rawValue)")
  }

  /// Reorder within the habit's own cadence group: swap with its neighbor in the
  /// same bucket. Grouping is by cadence, not stored order, so a global-index
  /// move would read as a no-op when the adjacent habit sits in another group.
  private func moveHabitWithinGroup(_ habitID: LorvexHabit.ID, by delta: Int) {
    let all = store.filteredHabits
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
    // Real best streak across visible habits (0 until per-habit stats load).
    let bestStreak = habits.compactMap { store.habitStats(for: $0.id)?.bestStreak }.max() ?? 0
    return HabitsWorkspaceStats(buckets: buckets, bestStreak: bestStreak)
  }

}
