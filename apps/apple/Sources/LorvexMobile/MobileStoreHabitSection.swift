import LorvexCore
import SwiftUI

/// The Habits screen's compact catalog: a row per active habit that matches
/// the search, an empty state while no habit is active, and the search's
/// no-results row while none match. The screen's navigation title names the
/// list, so the section draws no header of its own. Each row can move one
/// place in the manual order, except while a search narrows the list: the
/// habits between the ones shown are hidden, so a move there would be
/// ambiguous.
struct MobileStoreHabitsSection: View {
  let habits: [LorvexHabit]
  let isMutating: Bool
  let editHabit: (LorvexHabit) -> Void
  let deleteHabit: (LorvexHabit) async -> Bool
  let archiveHabit: (LorvexHabit) async -> Bool
  let complete: (LorvexHabit) async -> Bool
  let reset: (LorvexHabit) async -> Bool
  let toggleSkip: (LorvexHabit) async -> Bool
  let move: (LorvexHabit, MobileReorderDirection) -> Void
  let searchQuery: String
  let detailRoute: (LorvexHabit) -> MobileRoute

  var body: some View {
    Section {
      let activeHabits = habits.filter { !$0.archived }
      let matchingHabits = LorvexCatalogSearch.habits(activeHabits, query: searchQuery)
      let order = activeHabits.map(\.id)
      let isFiltering = LorvexCatalogSearch.isFiltering(searchQuery)
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
            moves: isFiltering
              ? nil
              : MobileHabitRowMoves(
                canMoveUp: MobileReorderDirection.moved(habit.id, in: order, .up) != nil,
                canMoveDown: MobileReorderDirection.moved(habit.id, in: order, .down) != nil,
                moveUp: { move(habit, .up) }, moveDown: { move(habit, .down) }),
            detailRoute: detailRoute(habit)
          )
        }
      }
      // No inline "New Habit" row — the toolbar ＋ is the single add affordance.
    }
  }
}

/// A habit row's one-place moves in the manual order: whether each applies and
/// what it does.
struct MobileHabitRowMoves {
  let canMoveUp: Bool
  let canMoveDown: Bool
  let moveUp: () -> Void
  let moveDown: () -> Void
}

/// One habit in the Habits list: icon tile, name, today's progress, the
/// milestone line, and the trailing completion ring. Tapping the row opens
/// the habit's detail. Skip Today (Undo Skip once skipped) and Edit ride the
/// leading swipe and Delete (confirmed) and Archive the trailing one; the
/// context menu offers the same actions plus complete / reset and, when
/// `moves` is set, Move Up and Move Down (also VoiceOver actions on the row).
struct MobileHabitRow: View {
  let habit: LorvexHabit
  let isMutating: Bool
  let editHabit: () -> Void
  let deleteHabit: () async -> Bool
  let archiveHabit: () async -> Bool
  let complete: () async -> Bool
  let reset: () async -> Bool
  let toggleSkip: () async -> Bool
  let moves: MobileHabitRowMoves?
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
        basis: .period,
        complete: { _ = await complete() },
        reset: { _ = await reset() }
      )
    }
    .padding(.vertical, LorvexDesign.Spacing.s)
    .accessibilityElement(children: .contain)
    // `allowsFullSwipe: false` — deleting a habit is irreversible (its streak and
    // completion history go with it), so it shouldn't ride a one-finger flick.
    // Tap-to-reveal then the confirmation dialog makes the destroy deliberate.
    // The button has no `destructive` role: that role collapses the row when the
    // button is tapped, and the dialog attached to the row would close with it.
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button {
        isConfirmingDelete = true
      } label: {
        Label(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "trash")
      }
      .mobileDestructiveSwipeStyle()
      .disabled(isMutating)
      .accessibilityIdentifier("mobileHabits.delete.\(habit.id)")

      archiveButton
        .mobileNeutralSwipeStyle()
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
      if habit.offersCompleteToday {
        Button {
          Task { _ = await complete() }
        } label: {
          Label(
            String(localized: "habits.detail.complete", defaultValue: "Complete Today", table: "Localizable", bundle: MobileL10n.bundle),
            systemImage: "checkmark.circle")
        }
        .disabled(isMutating)
      }
      if habit.offersResetToday {
        Button {
          Task { _ = await reset() }
        } label: {
          Label(
            String(localized: "habits.detail.reset", defaultValue: "Reset Today", table: "Localizable", bundle: MobileL10n.bundle),
            systemImage: "arrow.counterclockwise")
        }
        .disabled(isMutating)
      }

      skipButton

      Button {
        editHabit()
      } label: {
        Label(String(localized: "common.edit", defaultValue: "Edit", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "pencil")
      }
      .disabled(isMutating)

      if let moves {
        Divider()
        MobileReorderMenuItems(
          canMoveUp: moves.canMoveUp, canMoveDown: moves.canMoveDown,
          moveUp: moves.moveUp, moveDown: moves.moveDown)
        Divider()
      }

      archiveButton

      Button(role: .destructive) {
        isConfirmingDelete = true
      } label: {
        Label(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "trash")
      }
      .disabled(isMutating)
    }
    .mobileReorderActions(
      canMoveUp: moves?.canMoveUp ?? false, canMoveDown: moves?.canMoveDown ?? false,
      moveUp: { moves?.moveUp() }, moveDown: { moves?.moveDown() })
    .mobileDeleteConfirmation(
      isPresented: $isConfirmingDelete,
      title: MobileHabitDeleteCopy.title(for: habit),
      message: MobileHabitDeleteCopy.message
    ) {
      Task { _ = await deleteHabit() }
    }
  }

  /// Skip Today, or Undo Skip once today is set aside; absent while today holds
  /// a check-in, which a skip cannot share the day with. Skip Today's tint is
  /// cleared, so the swipe button takes the system's neutral gray: the day is
  /// set aside, not lost. Undo Skip draws in the due-soon orange.
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
  /// from the Habits screen's archived section. The swipe draws it in neutral
  /// gray (``SwiftUI/View/mobileNeutralSwipeStyle()``) rather than a color that
  /// implies loss.
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
