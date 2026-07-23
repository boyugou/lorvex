import LorvexCore
import SwiftUI

/// The shared defer control: a menu that lets you choose how far to push a task
/// — tomorrow, in a few days, or next week — instead of always landing on
/// tomorrow. Each option re-anchors to a storage-frame day and applies via
/// `onDefer`. Used by the task detail, the row context menu, and the Today list,
/// so deferring is consistent and offers a day choice everywhere.
struct TaskDeferMenu<MenuLabel: View>: View {
  @Bindable var store: AppStore
  /// Applies the chosen storage-frame defer date (e.g. `deferSelectedTask(until:)`
  /// or `deferTaskFromRow(_:until:)`).
  let onDefer: (Date) -> Void
  @ViewBuilder var menuLabel: () -> MenuLabel

  var body: some View {
    Menu {
      Button {
        deferBy(daysFromNow: 1)
      } label: {
        Label(
          String(localized: "date_chip.tomorrow", defaultValue: "Tomorrow", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "sun.max")
      }
      Button {
        deferBy(daysFromNow: 3)
      } label: {
        Label(
          String(localized: "task.defer.in_3_days", defaultValue: "In 3 days", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "calendar")
      }
      Button {
        deferBy(daysFromNow: 7)
      } label: {
        Label(
          String(localized: "date_chip.next_week", defaultValue: "Next Week", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "calendar.badge.clock")
      }
    } label: {
      menuLabel()
    }
  }

  private func deferBy(daysFromNow days: Int) {
    guard let date = store.deferStorageDate(daysFromNow: days) else { return }
    onDefer(date)
  }
}
