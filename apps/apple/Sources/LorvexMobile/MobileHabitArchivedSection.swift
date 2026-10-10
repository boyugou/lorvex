import LorvexCore
import SwiftUI

/// The Habits screen's archived habits, under a header that folds them away
/// (folded by default, remembered across launches). The header counts the
/// habits only while it hides them. Each row restores its habit with one tap;
/// deleting one for good sits behind a swipe or the context menu and a
/// confirmation that points at the row. Draws nothing while no habit is
/// archived.
struct MobileHabitArchivedSection: View {
  let habits: [LorvexHabit]
  let isMutating: Bool
  let restore: (LorvexHabit) -> Void
  /// The habit whose deletion the confirmation is asking about, shared with
  /// the active habits so one request shows at a time.
  @Binding var pendingDelete: LorvexHabit?
  /// Deletes a habit once the confirmation is accepted.
  let delete: (LorvexHabit) -> Void
  @AppStorage("habits.archived.collapsed") private var isCollapsed = true

  var body: some View {
    if !habits.isEmpty {
      Section {
        if !isCollapsed {
          ForEach(habits) { habit in
            row(habit)
          }
        }
      } header: {
        Button {
          lorvexAnimated(.snappy(duration: 0.2)) { isCollapsed.toggle() }
        } label: {
          HStack(spacing: LorvexDesign.Spacing.s) {
            Text(MobileHabitArchiveCopy.sectionTitle)
            if isCollapsed {
              Text("\(habits.count)")
                .monospacedDigit()
            }
            Spacer(minLength: 0)
            MobileFoldChevron(isExpanded: !isCollapsed)
          }
          .textCase(nil)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("mobileHabits.archived.toggle")
      }
      .accessibilityIdentifier("mobileHabits.archived")
    }
  }

  private func row(_ habit: LorvexHabit) -> some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      MobileIconTile(symbol: habit.tileSymbol, tint: LorvexDesign.Palette.neutral, size: 30)
      Text(userContent: habit.name)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button(MobileHabitArchiveCopy.restore) { restore(habit) }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isMutating)
        .accessibilityIdentifier("mobileHabits.archived.restore.\(habit.id)")
    }
    .padding(.vertical, LorvexDesign.Spacing.xxs)
    .accessibilityElement(children: .contain)
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      // No `destructive` role: it would collapse the row and take the
      // confirmation, which is attached to the row, with it.
      deleteButton(habit)
        .mobileDestructiveSwipeStyle()
    }
    .contextMenu {
      Button {
        restore(habit)
      } label: {
        Label(MobileHabitArchiveCopy.restore, systemImage: "arrow.uturn.backward")
      }
      .disabled(isMutating)
      deleteButton(habit, role: .destructive)
    }
    .mobileDeleteConfirmation(
      of: habit,
      pending: $pendingDelete,
      title: MobileHabitDeleteCopy.title(for: habit),
      message: MobileHabitDeleteCopy.message,
      delete: delete
    )
    .accessibilityIdentifier("mobileHabits.archived.row.\(habit.id)")
  }

  private func deleteButton(_ habit: LorvexHabit, role: ButtonRole? = nil) -> some View {
    Button(role: role) {
      pendingDelete = habit
    } label: {
      Label(
        String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle),
        systemImage: "trash")
    }
    .disabled(isMutating)
  }
}
