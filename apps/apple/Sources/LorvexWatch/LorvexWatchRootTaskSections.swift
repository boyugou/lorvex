import LorvexCore
import SwiftUI

#if os(watchOS)
  import WatchKit
#endif

extension LorvexWatchRootView {
  @ViewBuilder
  var taskSection: some View {
    Section(String(
      localized: "watch.section.current", defaultValue: "Current",
      table: "Localizable", bundle: WatchL10n.bundle)) {
      if let task = store.primaryTask {
        VStack(alignment: .leading, spacing: 4) {
          Text(task.title)
            .font(.headline)
            .multilineTextAlignment(.leading)
          if let minutes = task.estimatedMinutes {
            Text(String(format: String(
              localized: "watch.task.minutes", defaultValue: "%lld min",
              table: "Localizable", bundle: WatchL10n.bundle), minutes))
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
          String(
            format: String(
              localized: "watch.task.current.a11y", defaultValue: "Current focus: %@",
              table: "Localizable", bundle: WatchL10n.bundle),
            task.title
          )
        )
      } else {
        Text(String(
          localized: "watch.empty.no_focus", defaultValue: "No focus",
          table: "Localizable", bundle: WatchL10n.bundle))
          .font(.body)
          .foregroundStyle(.secondary)
          .accessibilityLabel(
            String(
              localized: "watch.empty.no_focus.a11y", defaultValue: "No current focus task",
              table: "Localizable", bundle: WatchL10n.bundle)
          )
      }
    }
  }

  @ViewBuilder
  var focusQueueSection: some View {
    let visibleTaskIDs = Set(LorvexWatchVisibleQueue.taskIDs(
      focusTaskIDs: store.focusTasks.map(\.id),
      activeTaskID: nil
    ))
    let queuedTasks = store.focusTasks.filter { visibleTaskIDs.contains($0.id) }
    if !queuedTasks.isEmpty {
      #if os(watchOS)
      LorvexWatchQueueNavigator(store: store, tasks: queuedTasks)
      #else
      Section(String(
        localized: "watch.section.next", defaultValue: "Next",
        table: "Localizable", bundle: WatchL10n.bundle)) {
        ForEach(queuedTasks) { task in
          LorvexWatchQueuedTaskRow(store: store, task: task)
        }
      }
      #endif
    }
  }
}

private struct LorvexWatchQueuedTaskRow: View {
  let store: LorvexWatchStore
  let task: LorvexTask

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "circle")
        .font(.caption2)
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(task.title)
          .font(.subheadline)
          .lineLimit(2)
        if let minutes = task.estimatedMinutes {
          Text(String(format: String(
            localized: "watch.task.minutes", defaultValue: "%lld min",
            table: "Localizable", bundle: WatchL10n.bundle), minutes))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      String(format: String(
        localized: "watch.task.next.a11y", defaultValue: "Next focus task: %@",
        table: "Localizable", bundle: WatchL10n.bundle), task.title)
    )
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      completeButton
    }
    .swipeActions(edge: .leading, allowsFullSwipe: false) {
      deferButton
    }
    .disabled(!store.canMutateQueuedTask)
  }

  private var completeButton: some View {
    Button {
      Task {
        await store.completeTask(id: task.id)
        #if os(watchOS)
        WKInterfaceDevice.current().play(store.error == nil ? .success : .failure)
        #endif
      }
    } label: {
      Label(String(
        localized: "watch.action.complete", defaultValue: "Complete",
        table: "Localizable", bundle: WatchL10n.bundle), systemImage: "checkmark.circle.fill")
    }
    .tint(.green)
    .accessibilityLabel(
      String(format: String(
        localized: "watch.action.complete.a11y", defaultValue: "Mark %@ complete",
        table: "Localizable", bundle: WatchL10n.bundle), task.title)
    )
  }

  private var deferButton: some View {
    Button {
      Task {
        await store.deferTaskToTomorrow(id: task.id)
        #if os(watchOS)
        WKInterfaceDevice.current().play(store.error == nil ? .click : .failure)
        #endif
      }
    } label: {
      Label(String(
        localized: "watch.action.tomorrow", defaultValue: "Tomorrow",
        table: "Localizable", bundle: WatchL10n.bundle), systemImage: "calendar.badge.clock")
    }
    .tint(.orange)
    .accessibilityLabel(
      String(format: String(
        localized: "watch.action.defer.a11y", defaultValue: "Defer %@ until tomorrow",
        table: "Localizable", bundle: WatchL10n.bundle), task.title)
    )
  }
}

extension LorvexWatchRootView {
  /// Today's habits with one-tap completion. Hidden when the snapshot
  /// carries no habits; done habits show a filled checkmark and ignore taps.
  @ViewBuilder
  var habitsSection: some View {
    if !store.habits.isEmpty {
      Section(String(
        localized: "watch.section.habits", defaultValue: "Habits",
        table: "Localizable", bundle: WatchL10n.bundle)) {
        ForEach(store.habits, id: \.id) { habit in
          Button {
            Task { await store.completeHabit(id: habit.id) }
          } label: {
            HStack(spacing: 6) {
              Image(systemName: habit.isDoneToday ? "checkmark.circle.fill" : (habit.icon ?? "repeat"))
                .foregroundStyle(habit.isDoneToday ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
              VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                  .font(.body)
                  .lineLimit(1)
                if habit.target > 1 {
                  Text("\(habit.completedToday)/\(habit.target)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
              }
            }
          }
          .disabled(habit.isDoneToday)
          .accessibilityIdentifier("watch.habit.\(habit.id)")
        }
      }
    }
  }
}
