import Foundation
import LorvexCore
import SwiftUI

/// The root watch view: shows the current primary focus task with a complete action.
///
/// Displays the task title when a focus plan is active, "No focus" when the plan
/// is empty, and a loading indicator while the store is refreshing. Errors are
/// surfaced as a brief inline message.
public struct LorvexWatchRootView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State var store: LorvexWatchStore

  public init(store: LorvexWatchStore) {
    self.store = store
  }

  public var body: some View {
    NavigationStack {
      content
        .navigationTitle(String(
          localized: "watch.nav.focus", defaultValue: "Focus",
          table: "Localizable", bundle: WatchL10n.bundle))
        #if os(watchOS) || os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // Revalidate the materialized logical day every time the watch scene
        // becomes active. A long-lived view identity can otherwise retain
        // yesterday's focus/habit state in memory even though the reader now
        // expires yesterday's on-disk snapshot.
        .task(id: scenePhase) {
          guard scenePhase == .active else { return }
          await store.refresh()
          await store.drainPendingCommands()
        }
        .userActivity(
          LorvexActivityType.openTask,
          isActive: store.primaryTask != nil
        ) { activity in
          guard let task = store.primaryTask else { return }
          let built = makeOpenTaskActivity(taskID: task.id, title: task.title)
          activity.title = built.title
          activity.isEligibleForHandoff = built.isEligibleForHandoff
          activity.requiredUserInfoKeys = built.requiredUserInfoKeys
          activity.addUserInfoEntries(from: built.userInfo ?? [:])
        }
    }
  }

  @ViewBuilder
  private var content: some View {
    if store.isLoading && store.primaryTask == nil {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      List {
        taskSection
        focusQueueSection
        habitsSection
        LorvexWatchCaptureSection(store: store)
        LorvexWatchDeliveryStatusSection(store: store)
        Section {
          Label(store.snapshotStatusText, systemImage: "arrow.triangle.2.circlepath")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityLabel(String(
              localized: "watch.status.a11y", defaultValue: "Watch data status",
              table: "Localizable", bundle: WatchL10n.bundle))
            .accessibilityValue(store.snapshotStatusText)
        }
        if store.primaryTask != nil {
          Section {
            LorvexWatchCompleteButton(store: store)
              .listRowBackground(Color.clear)
            LorvexWatchCancelButton(store: store)
              .listRowBackground(Color.clear)
            LorvexWatchDeferButton(store: store)
              .listRowBackground(Color.clear)
            LorvexWatchRemoveFocusButton(store: store)
              .listRowBackground(Color.clear)
            if let reason = store.completionUnavailableReason
              ?? store.focusMutationUnavailableReason
            {
              Text(reason)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
        }
        if store.error != nil {
          Section {
            VStack(alignment: .leading, spacing: 6) {
              Label(errorTitle, systemImage: errorSymbol)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.orange)
              Text(errorRemedy)
                .font(.caption2)
                .foregroundStyle(.secondary)
              Button {
                Task { await store.refresh() }
              } label: {
                Label(String(
                  localized: "watch.error.retry", defaultValue: "Retry",
                  table: "Localizable", bundle: WatchL10n.bundle), systemImage: "arrow.clockwise")
              }
              .controlSize(.small)
              .accessibilityHint(String(
                localized: "watch.error.retry.hint", defaultValue: "Reloads focus data from the snapshot or paired iPhone",
                table: "Localizable", bundle: WatchL10n.bundle))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(errorTitle). \(errorRemedy)")
          }
        }
      }
      #if os(watchOS)
      .listStyle(.carousel)
      #endif
    }
  }

  // MARK: - Error classification (glance-friendly, with a remedy)

  /// True when the failure is a snapshot-unavailable error (the watch
  /// couldn't read its App Group data and typically needs the phone to
  /// publish a fresh snapshot), vs a generic load failure.
  private var errorIsSnapshotUnavailable: Bool {
    guard let snapshotError = store.error as? LorvexWatchSnapshotError else { return false }
    if case .unavailable = snapshotError { return true }
    return false
  }

  /// Short headline for the error banner.
  private var errorTitle: String {
    errorIsSnapshotUnavailable
      ? String(
        localized: "watch.error.unavailable.title", defaultValue: "Focus data unavailable",
        table: "Localizable", bundle: WatchL10n.bundle)
      : String(
        localized: "watch.error.load.title", defaultValue: "Couldn't load focus",
        table: "Localizable", bundle: WatchL10n.bundle)
  }

  private var errorSymbol: String {
    errorIsSnapshotUnavailable ? "iphone.slash" : "exclamationmark.triangle"
  }

  /// What the user can do about it — a remedy, not a raw error string.
  private var errorRemedy: String {
    errorIsSnapshotUnavailable
      ? String(
        localized: "watch.error.unavailable.remedy", defaultValue: "Open Lorvex on your iPhone to sync, then retry.",
        table: "Localizable", bundle: WatchL10n.bundle)
      : String(
        localized: "watch.error.load.remedy", defaultValue: "Retry, or open Lorvex on your iPhone if this persists.",
        table: "Localizable", bundle: WatchL10n.bundle)
  }

}
