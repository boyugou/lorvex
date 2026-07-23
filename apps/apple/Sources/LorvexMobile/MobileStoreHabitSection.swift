import LorvexCore
import SwiftUI

struct MobileStoreHabitsSection: View {
  let habits: [LorvexHabit]?
  let isMutating: Bool
  let editHabit: (LorvexHabit) -> Void
  let deleteHabit: (LorvexHabit) async -> Bool
  let complete: (LorvexHabit) async -> Bool
  let reset: (LorvexHabit) async -> Bool
  let searchQuery: String
  let displayLimit: Int?
  let viewAll: (() -> Void)?
  let detailRoute: ((LorvexHabit) -> MobileRoute)?

  init(
    habits: [LorvexHabit]?,
    isMutating: Bool,
    editHabit: @escaping (LorvexHabit) -> Void,
    deleteHabit: @escaping (LorvexHabit) async -> Bool,
    complete: @escaping (LorvexHabit) async -> Bool,
    reset: @escaping (LorvexHabit) async -> Bool,
    searchQuery: String = "",
    displayLimit: Int? = nil,
    viewAll: (() -> Void)? = nil,
    detailRoute: ((LorvexHabit) -> MobileRoute)? = nil
  ) {
    self.habits = habits
    self.isMutating = isMutating
    self.editHabit = editHabit
    self.deleteHabit = deleteHabit
    self.complete = complete
    self.reset = reset
    self.searchQuery = searchQuery
    self.displayLimit = displayLimit
    self.viewAll = viewAll
    self.detailRoute = detailRoute
  }

  var body: some View {
    Section(String(localized: "destination.habits", defaultValue: "Habits", table: "Localizable", bundle: MobileL10n.bundle)) {
      let allActiveHabits = habits?.filter { !$0.archived } ?? []
      let matchingHabits = LorvexCatalogSearch.habits(allActiveHabits, query: searchQuery)
      let visibleHabitCount = displayLimit.map { min(matchingHabits.count, $0) } ?? matchingHabits.count
      let activeHabits = matchingHabits.prefix(visibleHabitCount)
      let hiddenHabitCount = max(0, matchingHabits.count - visibleHabitCount)
      if habits == nil {
        MobileSkeletonRows(count: displayLimit ?? 4, showsTrailingDetail: true)
      } else if allActiveHabits.isEmpty {
        MobileEmptyState(
          icon: "repeat",
          title: String(localized: "habits.empty.no_active", defaultValue: "No Active Habits", table: "Localizable", bundle: MobileL10n.bundle),
          message: String(localized: "habits.empty.no_active.message", defaultValue: "Tap ＋ to start a habit you want to build.", table: "Localizable", bundle: MobileL10n.bundle))
      } else if activeHabits.isEmpty {
        ContentUnavailableView.search(text: searchQuery)
      } else {
        ForEach(Array(activeHabits)) { habit in
          MobileHabitRow(
            habit: habit,
            isMutating: isMutating,
            editHabit: { editHabit(habit) },
            deleteHabit: { await deleteHabit(habit) },
            complete: { await complete(habit) },
            reset: { await reset(habit) },
            detailRoute: detailRoute.map { $0(habit) }
          )
        }
      }

      if hiddenHabitCount > 0, let viewAll {
        Button(action: viewAll) {
          Label(String(localized: "habits.view_all", defaultValue: "View All Habits", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "repeat")
        }
        .accessibilityIdentifier("mobileHabits.viewAll")
      }
      // No inline "New Habit" row — the toolbar ＋ is the single add affordance,
      // and Today's habits summary is read-only (create lives on the Habits tab).
    }
  }
}

private struct MobileHabitRow: View {
  let habit: LorvexHabit
  let isMutating: Bool
  let editHabit: () -> Void
  let deleteHabit: () async -> Bool
  let complete: () async -> Bool
  let reset: () async -> Bool
  let detailRoute: MobileRoute?

  @State private var isConfirmingDelete = false

  private var actionAccent: Color { .accentColor }

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      detailLabel
        .frame(maxWidth: .infinity, alignment: .leading)
      MobileHabitCompletionRing(
        habit: habit,
        isMutating: isMutating,
        complete: { _ = await complete() },
        reset: { _ = await reset() }
      )
    }
    .padding(.vertical, LorvexDesign.Spacing.s)
    .accessibilityElement(children: .contain)
    // `allowsFullSwipe: false` — deleting a habit is irreversible (its streak and
    // completion history go with it), so it shouldn't ride a one-finger flick.
    // Tap-to-reveal then the confirmation dialog makes the destroy deliberate.
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button(role: .destructive) {
        isConfirmingDelete = true
      } label: {
        Label(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "trash")
      }
      .disabled(isMutating)
      .accessibilityIdentifier("mobileHabits.delete.\(habit.id)")
    }
    .swipeActions(edge: .leading, allowsFullSwipe: false) {
      Button {
        editHabit()
      } label: {
        Label(String(localized: "common.edit", defaultValue: "Edit", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "pencil")
      }
      .tint(actionAccent)
      .disabled(isMutating)
      .accessibilityIdentifier("mobileHabits.edit.\(habit.id)")
    }
    .contextMenu {
      Button {
        Task {
          if habit.isCompleteToday {
            _ = await reset()
          } else {
            _ = await complete()
          }
        }
      } label: {
        Label(
          habit.isCompleteToday
            ? String(localized: "habits.detail.reset", defaultValue: "Reset Today", table: "Localizable", bundle: MobileL10n.bundle)
            : String(localized: "habits.detail.complete", defaultValue: "Complete Today", table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: habit.isCompleteToday ? "arrow.counterclockwise" : "checkmark.circle")
      }
      .disabled(isMutating)

      Button {
        editHabit()
      } label: {
        Label(String(localized: "common.edit", defaultValue: "Edit", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "pencil")
      }
      .disabled(isMutating)

      Button(role: .destructive) {
        isConfirmingDelete = true
      } label: {
        Label(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "trash")
      }
      .disabled(isMutating)
    }
    .confirmationDialog(
      String(
        format: String(localized: "habits.row.delete_confirm.title", defaultValue: "Delete habit “%@”?", table: "Localizable", bundle: MobileL10n.bundle),
        habit.name),
      isPresented: $isConfirmingDelete,
      titleVisibility: .visible
    ) {
      Button(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle), role: .destructive) {
        Task { _ = await deleteHabit() }
      }
      Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: MobileL10n.bundle), role: .cancel) {}
    } message: {
      Text(String(localized: "habits.row.delete_confirm.message", defaultValue: "This removes its completion history.", table: "Localizable", bundle: MobileL10n.bundle))
    }
  }

  @ViewBuilder
  private var detailLabel: some View {
    if let detailRoute {
      // Navigate on tap WITHOUT the trailing disclosure chevron — the row is
      // obviously tappable and the chevron is just clutter (a hidden zero-opacity
      // NavigationLink carries the navigation; the content draws on top).
      ZStack {
        NavigationLink(value: detailRoute) { EmptyView() }
          .opacity(0)
        HStack(spacing: LorvexDesign.Spacing.m) {
          habitSummary
          Spacer(minLength: LorvexDesign.Spacing.s)
        }
      }
    } else {
      HStack(spacing: LorvexDesign.Spacing.m) {
        habitSummary
        Spacer(minLength: LorvexDesign.Spacing.s)
      }
    }
  }

  private var habitSummary: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      MobileIconTile(icon: habit.icon, fallback: "repeat", tint: habit.tileTint, size: 30)
      VStack(alignment: .leading, spacing: 3) {
        Text(habit.name)
          .font(.body)
          .lineLimit(1)
        Text(habit.todayProgressText)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        if let milestone = habit.milestone, habit.showsMilestoneStrip {
          MobileHabitMilestoneProgressView(
            milestone: milestone, frequencyType: habit.frequencyType, tint: habit.tileTint)
        }
      }
    }
  }
}
