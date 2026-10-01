import LorvexCore
import SwiftUI

/// The watch's first page: Today's list, in Today's order.
///
/// When the lead task's saved time is running, the lead heads the page: its
/// title, "Until" and the time its time ends, and its ring, which fills as the
/// time passes and completes the task when tapped. Every other task is a row
/// whose circle completes it. Tapping a task's title opens its actions (Start
/// or Pause, Tomorrow, Cancel); a row's swipes reach the ones the phone's do,
/// leading Start or Pause and trailing Tomorrow. An action that failed to save
/// shows above the list, and once the phone's copy is hours old a footer says
/// when it synced. With nothing left, the page says so and counts what got
/// done.
struct LorvexWatchTodayPage: View {
  @Bindable var store: LorvexWatchStore
  @State private var actionTask: LorvexWatchTaskReference?
  @State private var didOpenActions = false
  private let opensActions: Bool

  /// `opensActions` opens the lead task's actions once the list loads; the
  /// headless capture path uses it to photograph the sheet.
  init(store: LorvexWatchStore, opensActions: Bool = false) {
    self.store = store
    self.opensActions = opensActions
  }

  var body: some View {
    TimelineView(.everyMinute) { context in
      let nowMinutes = store.productMinutes(at: context.date)
      content(ordered: store.orderedTasks(at: nowMinutes), nowMinutes: nowMinutes)
    }
    .navigationTitle(LorvexWatchCalmCopy.todayTitle)
    .sheet(item: $actionTask) { reference in
      LorvexWatchTaskActionsSheet(store: store, taskID: reference.id)
    }
    .onChange(of: store.tasks.isEmpty, initial: true) { _, isEmpty in
      guard opensActions, !didOpenActions, !isEmpty,
        let lead = store.lead(at: store.now()) ?? store.tasks.first
      else {
        return
      }
      didOpenActions = true
      actionTask = LorvexWatchTaskReference(id: lead.id)
    }
    .accessibilityIdentifier("watch.today")
  }

  @ViewBuilder
  private func content(ordered: [LorvexTask], nowMinutes: Int) -> some View {
    if ordered.isEmpty {
      if store.error != nil {
        LorvexWatchErrorNote(store: store)
      } else {
        emptyDay
      }
    } else {
      List {
        // An action that failed while tasks are listed: the haptic alone is
        // easy to miss.
        if store.error != nil {
          Label(LorvexWatchCalmCopy.actionFailed, systemImage: "exclamationmark.triangle.fill")
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(LorvexDesign.Palette.warning)
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("watch.today.actionError")
        }
        if let lead = ordered.first, let time = store.runningTime(of: lead, at: nowMinutes) {
          runningLead(lead, time: time, nowMinutes: nowMinutes)
          rows(ordered.dropFirst(), nowMinutes: nowMinutes)
        } else {
          rows(ordered[...], nowMinutes: nowMinutes)
        }
        if store.moreCount > 0 {
          Text(LorvexWatchCalmCopy.moreToday(store.moreCount))
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowBackground(Color.clear)
        }
        if let age = store.staleAgeLabel {
          Label(LorvexWatchCalmCopy.synced(age), systemImage: "clock.arrow.circlepath")
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("watch.today.staleAge")
        }
      }
    }
  }

  /// The lead whose saved time contains the clock: its title (which opens its
  /// actions), when its time ends, and the ring that completes it.
  private func runningLead(_ task: LorvexTask, time: Range<Int>, nowMinutes: Int) -> some View {
    VStack(spacing: LorvexDesign.Spacing.s) {
      Button {
        actionTask = LorvexWatchTaskReference(id: task.id)
      } label: {
        VStack(spacing: LorvexDesign.Spacing.xxs) {
          Text(task.title)
            .font(LorvexDesign.Typography.primaryEmphasis)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.85)
          Text(LorvexWatchCalmCopy.until(time.upperBound))
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(LorvexDesign.Palette.accent)
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint(LorvexWatchCalmCopy.actionsHint)
      LorvexWatchCompleteButton(
        title: task.title,
        style: .ring(progress: Self.progress(of: time, at: nowMinutes), diameter: 52),
        isEnabled: store.canMutateTasks
      ) {
        await store.completeTask(id: task.id)
        return store.error == nil
      }
      .accessibilityIdentifier("watch.today.lead.done")
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .listRowBackground(Color.clear)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("watch.today.lead")
  }

  private func rows(_ tasks: ArraySlice<LorvexTask>, nowMinutes: Int) -> some View {
    ForEach(tasks) { task in
      LorvexWatchTaskRow(
        task: task,
        line: LorvexWatchTaskLine.make(
          task: task, time: store.savedTimes[task.id], nowMinutes: nowMinutes,
          logicalDay: store.logicalDay),
        canComplete: store.canMutateTasks,
        complete: {
          await store.completeTask(id: task.id)
          return store.error == nil
        },
        openActions: { actionTask = LorvexWatchTaskReference(id: task.id) }
      )
      .swipeActions(edge: .leading, allowsFullSwipe: true) {
        Button {
          Task {
            if task.status == .inProgress {
              await store.pauseTask(id: task.id)
            } else {
              await store.startTask(id: task.id)
            }
          }
        } label: {
          task.status == .inProgress
            ? Label(
              String(localized: "watch.action.pause", defaultValue: "Pause", table: "Localizable", bundle: WatchL10n.bundle),
              systemImage: "pause.fill")
            : Label(
              String(localized: "watch.action.start", defaultValue: "Start", table: "Localizable", bundle: WatchL10n.bundle),
              systemImage: "play.fill")
        }
        .tint(LorvexDesign.Palette.accent)
        .disabled(!store.canMutateTasks)
      }
      .swipeActions(edge: .trailing, allowsFullSwipe: true) {
        Button {
          Task { await store.deferTaskToTomorrow(id: task.id) }
        } label: {
          Label(
            String(localized: "watch.action.tomorrow", defaultValue: "Tomorrow", table: "Localizable", bundle: WatchL10n.bundle),
            systemImage: "calendar.badge.clock")
        }
        .tint(LorvexDesign.Palette.neutral)
        .disabled(!store.canMutateTasks)
      }
    }
  }

  private var emptyDay: some View {
    VStack(spacing: LorvexDesign.Spacing.xs) {
      Image(systemName: store.completedTodayCount > 0 ? "checkmark.circle.fill" : "checkmark.circle")
        .font(LorvexDesign.Typography.sectionHeader)
        .foregroundStyle(store.completedTodayCount > 0 ? LorvexDesign.Palette.done : .secondary)
      Text(LorvexWatchCalmCopy.allClear)
        .font(LorvexDesign.Typography.primaryEmphasis)
      Text(LorvexWatchCalmCopy.emptyLine(done: store.completedTodayCount))
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, LorvexDesign.Spacing.m)
    .accessibilityElement(children: .combine)
  }

  /// How much of a running time has passed, 0 at its start and 1 at its end.
  nonisolated static func progress(of time: Range<Int>, at nowMinutes: Int) -> Double {
    guard !time.isEmpty else { return 0 }
    let elapsed = Double(nowMinutes - time.lowerBound) / Double(time.count)
    return min(max(elapsed, 0), 1)
  }
}
