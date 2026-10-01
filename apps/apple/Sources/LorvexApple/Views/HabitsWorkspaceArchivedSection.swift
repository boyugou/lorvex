import LorvexCore
import SwiftUI

extension HabitsWorkspaceView {
  /// List of archived habits with restore + permanent-delete, so the archive
  /// action has a reachable inverse (otherwise archiving is a dead end). Draws
  /// nothing while no habit is archived.
  @ViewBuilder
  var archivedSection: some View {
    if !store.archivedHabits.isEmpty {
      WorkspaceDashboardLane {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
          Label(
            String(localized: "habits.archived.section", defaultValue: "Archived", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "archivebox"
          )
          .font(LorvexDesign.Typography.secondaryText.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("habits.archived.section")

          ForEach(store.archivedHabits) { habit in
            archivedRow(habit)
            Divider().opacity(0.4)
          }
        }
        .padding(.horizontal, LorvexDesign.Spacing.l)
        .padding(.bottom, LorvexDesign.Spacing.m)
      }
      // Permanent delete from the archived list is irreversible (loses history);
      // confirm it the same way the active habit card's Delete does.
      .confirmationDialog(
        archivedHabitPendingDeletion.map {
          String(
            format: String(
              localized: "habits.row.delete_confirm.title", defaultValue: "Delete habit “%@”?",
              table: "Localizable",
              bundle: LorvexL10n.bundle),
            $0.name)
        } ?? "",
        isPresented: Binding(
          get: { archivedHabitPendingDeletion != nil },
          set: { if !$0 { archivedHabitPendingDeletion = nil } }
        ),
        titleVisibility: .visible,
        presenting: archivedHabitPendingDeletion
      ) { habit in
        Button(
          String(localized: "habits.row.delete_confirm.delete", defaultValue: "Delete Habit", table: "Localizable", bundle: LorvexL10n.bundle),
          role: .destructive
        ) {
          Task { await store.deleteHabit(habit) }
        }
        Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: LorvexL10n.bundle), role: .cancel) {}
      } message: { _ in
        Text(LocalizedStringResource("habits.row.delete_confirm.message", defaultValue: "This removes its completion history.", table: "Localizable", bundle: LorvexL10n.bundle))
      }
    }
  }

  func archivedRow(_ habit: LorvexHabit) -> some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      Image(systemName: habit.icon ?? "repeat.circle")
        .foregroundStyle(.secondary)
        .frame(width: 20)
      Text(habit.name)
        .font(LorvexDesign.Typography.primaryText)
        .lineLimit(1)
      Spacer(minLength: LorvexDesign.Spacing.m)
      Button(String(localized: "habits.row.restore", defaultValue: "Restore", table: "Localizable", bundle: LorvexL10n.bundle)) {
        Task { await store.setHabitArchived(habit, archived: false) }
      }
      .buttonStyle(.bordered)
      Button(role: .destructive) {
        archivedHabitPendingDeletion = habit
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .help(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityLabel(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: LorvexL10n.bundle))
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .accessibilityElement(children: .combine)
  }
}
