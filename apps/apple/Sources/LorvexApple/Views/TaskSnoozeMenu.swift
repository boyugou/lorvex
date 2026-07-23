import LorvexCore
import SwiftUI

/// The shared "Snooze until…" control: a menu that hides a task from the day
/// surfaces until a chosen day by writing `available_from` — Tomorrow, Next
/// Week, or a Custom date picked with a ``LorvexDateChip``. Distinct from
/// ``TaskDeferMenu``, which pushes `planned_date`; snoozing parks
/// not-yet-actionable work without touching the planned day. Each option
/// re-anchors to a storage-frame day and applies via `onSnooze`. Used by the
/// row context menu and the detail actions menu, so snoozing is consistent and
/// offers a day choice everywhere.
struct TaskSnoozeMenu<MenuLabel: View>: View {
  @Bindable var store: AppStore
  /// Applies the chosen storage-frame snooze date (writes `available_from` via
  /// `snoozeTask(id:until:)` / `snoozeSelectedTask(until:)`).
  let onSnooze: (Date) -> Void
  @ViewBuilder var menuLabel: () -> MenuLabel

  @State private var showsCustom = false
  @State private var customDate = Date()

  var body: some View {
    Menu {
      Button {
        snoozeBy(daysFromNow: 1)
      } label: {
        Label(
          String(localized: "date_chip.tomorrow", defaultValue: "Tomorrow", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "sun.max")
      }
      Button {
        snoozeBy(daysFromNow: 7)
      } label: {
        Label(
          String(localized: "date_chip.next_week", defaultValue: "Next Week", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "calendar.badge.clock")
      }
      Divider()
      Button {
        // Seed the custom picker on today so the popover's chip opens on a
        // sensible month even before the user picks.
        customDate = Date()
        showsCustom = true
      } label: {
        Label(
          String(localized: "task.snooze.custom", defaultValue: "Custom Date…", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "calendar")
      }
      .accessibilityIdentifier("task.snooze.custom")
    } label: {
      menuLabel()
    }
    .popover(isPresented: $showsCustom, arrowEdge: .bottom) {
      customSnoozePopover
    }
  }

  private var customSnoozePopover: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      Text(LocalizedStringResource("task.snooze.until", defaultValue: "Snooze until", table: "Localizable", bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.secondaryText.weight(.medium))
        .foregroundStyle(.secondary)
      LorvexDateChip(
        date: customDate,
        placeholder: String(
          localized: "task_detail.metadata.set_date", defaultValue: "Set Date",
          table: "Localizable",
          bundle: LorvexL10n.bundle)
      ) { selected in
        customDate = selected
        showsCustom = false
        onSnooze(PlannedDayBridge.storageDate(forLocalInstant: selected))
      }
      .accessibilityIdentifier("task.snooze.custom.chip")
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(width: 260)
    .accessibilityIdentifier("task.snooze.custom.popover")
  }

  private func snoozeBy(daysFromNow days: Int) {
    guard let date = store.deferStorageDate(daysFromNow: days) else { return }
    onSnooze(date)
  }
}
