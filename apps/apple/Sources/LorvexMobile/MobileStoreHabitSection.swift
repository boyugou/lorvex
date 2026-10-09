import LorvexCore
import SwiftUI

/// The Habits screen's compact catalog: a row per active habit that matches
/// the search, an empty state while no habit is active, and the search's
/// no-results row while none match. The screen's navigation title names the
/// list, so the section draws no header of its own.
struct MobileStoreHabitsSection: View {
  let habits: [LorvexHabit]
  let isMutating: Bool
  let editHabit: (LorvexHabit) -> Void
  let deleteHabit: (LorvexHabit) async -> Bool
  let archiveHabit: (LorvexHabit) async -> Bool
  let complete: (LorvexHabit) async -> Bool
  let reset: (LorvexHabit) async -> Bool
  let toggleSkip: (LorvexHabit) async -> Bool
  let searchQuery: String
  let detailRoute: (LorvexHabit) -> MobileRoute

  var body: some View {
    Section {
      let activeHabits = habits.filter { !$0.archived }
      let matchingHabits = LorvexCatalogSearch.habits(activeHabits, query: searchQuery)
      if activeHabits.isEmpty {
        MobileEmptyState(
          icon: "repeat",
          title: String(localized: "habits.empty.no_active", defaultValue: "No Active Habits", table: "Localizable", bundle: MobileL10n.bundle),
          message: String(localized: "habits.empty.no_active.message", defaultValue: "Tap ＋ to start a habit you want to build.", table: "Localizable", bundle: MobileL10n.bundle),
          pointsAtToolbarAdd: true)
      } else if matchingHabits.isEmpty {
        MobileEmptyState.search(text: searchQuery)
      } else {
        ForEach(matchingHabits) { habit in
          MobileHabitRow(
            habit: habit,
            isMutating: isMutating,
            editHabit: { editHabit(habit) },
            deleteHabit: { await deleteHabit(habit) },
            archiveHabit: { await archiveHabit(habit) },
            complete: { await complete(habit) },
            reset: { await reset(habit) },
            toggleSkip: { await toggleSkip(habit) },
            detailRoute: detailRoute(habit)
          )
        }
      }
      // No inline "New Habit" row — the toolbar ＋ is the single add affordance.
    }
  }
}

/// One habit in the Habits list: icon tile, name, today's progress, the
/// milestone line, and the trailing completion ring. Tapping the row opens
/// the habit's detail. Skip Today (Undo Skip once skipped) and Edit ride the
/// leading swipe and Delete (confirmed) and Archive the trailing one; the
/// context menu offers the same actions plus complete / reset.
struct MobileHabitRow: View {
  let habit: LorvexHabit
  let isMutating: Bool
  let editHabit: () -> Void
  let deleteHabit: () async -> Bool
  let archiveHabit: () async -> Bool
  let complete: () async -> Bool
  let reset: () async -> Bool
  let toggleSkip: () async -> Bool
  let detailRoute: MobileRoute

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

      archiveButton
        .accessibilityIdentifier("mobileHabits.archive.\(habit.id)")
    }
    .swipeActions(edge: .leading, allowsFullSwipe: false) {
      skipButton
        .accessibilityIdentifier("mobileHabits.skip.\(habit.id)")

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

      skipButton

      Button {
        editHabit()
      } label: {
        Label(String(localized: "common.edit", defaultValue: "Edit", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "pencil")
      }
      .disabled(isMutating)

      archiveButton

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

  /// Skip Today, or Undo Skip once today is set aside; absent while today holds
  /// a check-in, which a skip cannot share the day with. Untinted, so the swipe
  /// button takes the system's neutral gray: the day is set aside, not lost.
  @ViewBuilder
  private var skipButton: some View {
    if let action = LorvexHabitSkip.action(for: habit) {
      Button {
        Task { _ = await toggleSkip() }
      } label: {
        Label(
          MobileHabitSkipCopy.title(for: action),
          systemImage: MobileHabitSkipCopy.systemImage(for: action))
      }
      .tint(action == .unskip ? LorvexDesign.Palette.dueSoon : nil)
      .disabled(isMutating)
    }
  }

  /// Archive needs no confirmation: the habit keeps its history and returns
  /// from the Habits screen's archived section. Untinted, so the swipe button
  /// takes the system's neutral gray rather than a color that implies loss.
  private var archiveButton: some View {
    Button {
      Task { _ = await archiveHabit() }
    } label: {
      Label(MobileHabitArchiveCopy.archive, systemImage: "archivebox")
    }
    .disabled(isMutating)
  }

  /// No trailing disclosure chevron: the row is plainly tappable, and the
  /// chevron would sit between the summary and the completion ring.
  private var detailLabel: some View {
    NavigationLink(value: detailRoute) {
      HStack(spacing: LorvexDesign.Spacing.m) {
        MobileHabitSummary(habit: habit)
        Spacer(minLength: LorvexDesign.Spacing.s)
      }
    }
    .navigationLinkIndicatorVisibility(.hidden)
  }
}
