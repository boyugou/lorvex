import Foundation
import LorvexCore
import SwiftUI

/// The pages the Digital Crown moves through, in order.
public enum LorvexWatchPage: String, Hashable, Sendable {
  case today, habits, capture
}

/// The root watch view: vertical pages on the Digital Crown. The first page is
/// Today's list, headed by the lead task and its ring while its saved time
/// runs; the next pages hold today's habits, then capture with sync status.
public struct LorvexWatchRootView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State var store: LorvexWatchStore
  @State private var page: LorvexWatchPage
  private let opensActions: Bool

  /// `initialPage` and `opensActions` are the headless capture path's way to
  /// land on a page or on the lead task's actions; the app opens on Today.
  public init(store: LorvexWatchStore, initialPage: LorvexWatchPage = .today, opensActions: Bool = false) {
    self.store = store
    _page = State(initialValue: initialPage)
    self.opensActions = opensActions
  }

  public var body: some View {
    NavigationStack {
      content
        // Revalidate the materialized logical day every time the watch scene
        // becomes active. A long-lived view identity can otherwise retain
        // yesterday's task/habit state in memory even though the reader now
        // expires yesterday's on-disk snapshot.
        .task(id: scenePhase) {
          guard scenePhase == .active else { return }
          await store.refresh()
          if store.needsReplica {
            await store.requestReplicaAndRefresh()
          }
          await store.drainPendingCommands()
        }
        .userActivity(
          LorvexActivityType.openTask,
          isActive: store.lead(at: Date()) != nil
        ) { activity in
          guard let task = store.lead(at: Date()) else { return }
          configureOpenTaskActivity(activity, taskID: task.id, title: task.title)
        }
    }
  }

  /// The pages the Digital Crown moves through: Today, habits, then capture
  /// and sync status. The habits page is left out when there are none.
  @ViewBuilder
  private var content: some View {
    if store.isLoading && store.tasks.isEmpty && store.error == nil {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      TabView(selection: $page) {
        LorvexWatchTodayPage(store: store, opensActions: opensActions)
          .tag(LorvexWatchPage.today)
        if !store.habits.isEmpty {
          LorvexWatchHabitsPage(store: store)
            .tag(LorvexWatchPage.habits)
        }
        List {
          LorvexWatchCaptureSection(store: store)
          LorvexWatchDeliveryStatusSection(store: store)
          Section {
            Label(store.snapshotStatusText, systemImage: "arrow.triangle.2.circlepath")
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.secondary)
              .accessibilityLabel(String(
                localized: "watch.status.a11y", defaultValue: "Watch data status",
                table: "Localizable", bundle: WatchL10n.bundle))
              .accessibilityValue(store.snapshotStatusText)
          }
        }
        .tag(LorvexWatchPage.capture)
      }
      #if os(watchOS)
        .tabViewStyle(.verticalPage)
      #endif
    }
  }
}
