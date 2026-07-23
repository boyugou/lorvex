import LorvexCore
import SwiftUI
#if os(watchOS)
  import WatchKit
#endif

struct LorvexWatchQueueNavigator: View {
  @Bindable var store: LorvexWatchStore
  let tasks: [LorvexTask]
  @State private var crownPosition = 0.0

  private var selectedIndex: Int {
    LorvexWatchQueueSelection.clampedIndex(for: crownPosition, count: tasks.count)
  }

  private var selectedTask: LorvexTask? {
    guard tasks.indices.contains(selectedIndex) else { return nil }
    return tasks[selectedIndex]
  }

  var body: some View {
    Section(String(
      localized: "watch.section.next", defaultValue: "Next",
      table: "Localizable", bundle: WatchL10n.bundle)) {
      if let task = selectedTask {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            Text("\(selectedIndex + 1)/\(tasks.count)")
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
              Text(task.title)
                .font(.subheadline.weight(.semibold))
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

          HStack {
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
                table: "Localizable", bundle: WatchL10n.bundle), systemImage: "checkmark")
            }
            .tint(.green)

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
                table: "Localizable", bundle: WatchL10n.bundle), systemImage: "calendar")
            }
            .tint(.orange)
          }
          .labelStyle(.iconOnly)
          .disabled(!store.canMutateQueuedTask)
        }
        #if os(watchOS)
        .focusable(true)
        .digitalCrownRotation(
          $crownPosition,
          from: 0,
          through: Double(max(tasks.count - 1, 0)),
          by: 1,
          sensitivity: .medium,
          isContinuous: false)
        #endif
        .onChange(of: tasks.map(\.id)) { _, _ in
          crownPosition = LorvexWatchQueueSelection.clampedPosition(
            crownPosition, count: tasks.count)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
          LorvexWatchQueueSelection.accessibilityLabel(
            title: task.title,
            selectedIndex: selectedIndex,
            count: tasks.count
          )
        )
      }
    }
  }
}
