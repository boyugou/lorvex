import LorvexCore
import SwiftUI

/// What a task row can do on iPhone and iPad: complete the task, start or
/// pause it, and move it to a later day. Hosts build it with
/// ``MobileStore/rowActions(for:afterSuccess:)``, so every row surface offers
/// the same actions.
struct MobileTaskRowActions {
  var complete: () async -> Void
  var start: () async -> Void
  var pause: () async -> Void
  /// Moves the task to the day `days` days after today.
  var deferByDays: (Int) async -> Void
}

/// The days a task can be deferred by from a row's context menu or the task
/// detail: tomorrow, in three days, or next week, the choices the macOS defer
/// menu offers.
enum MobileDeferChoice: Int, CaseIterable, Identifiable {
  case tomorrow = 1
  case inThreeDays = 3
  case nextWeek = 7

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .tomorrow:
      String(
        localized: "date_chip.tomorrow", defaultValue: "Tomorrow", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .inThreeDays:
      String(
        localized: "task.defer.in_3_days", defaultValue: "In 3 days", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .nextWeek:
      String(
        localized: "date_chip.next_week", defaultValue: "Next Week", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }

  var systemImage: String {
    switch self {
    case .tomorrow: "sun.max"
    case .inThreeDays: "calendar"
    case .nextWeek: "calendar.badge.clock"
    }
  }
}

/// A Defer menu listing the ``MobileDeferChoice`` days.
struct MobileDeferMenu<MenuLabel: View>: View {
  let deferByDays: (Int) async -> Void
  @ViewBuilder var label: () -> MenuLabel

  var body: some View {
    Menu {
      ForEach(MobileDeferChoice.allCases) { choice in
        Button {
          Task { await deferByDays(choice.rawValue) }
        } label: {
          Label(choice.title, systemImage: choice.systemImage)
        }
      }
    } label: {
      label()
    }
  }
}

/// The words the row actions and the task detail share.
enum MobileTaskActionCopy {
  static var start: String {
    String(
      localized: "action.start", defaultValue: "Start", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var pause: String {
    String(
      localized: "task.action.pause", defaultValue: "Pause", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var complete: String {
    String(
      localized: "action.complete", defaultValue: "Complete", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var reopen: String {
    String(
      localized: "action.reopen", defaultValue: "Reopen", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  /// What a task's completion circle does: Complete for an open task, Reopen
  /// for a done one.
  static func completionToggle(isDone: Bool) -> String {
    isDone ? reopen : complete
  }

  static var deferTask: String {
    String(
      localized: "action.defer", defaultValue: "Defer", table: "Localizable",
      bundle: MobileL10n.bundle)
  }
}

/// The shared row actions (``MobileTaskRowActions``): Start or Pause on the
/// leading swipe; Complete (the full swipe) and Defer to tomorrow on the
/// trailing swipe; and a context menu with Complete, Start or Pause, and a
/// Defer menu of days. Used by the plain action row and the batch-selectable
/// workspace row; the latter passes `isBatchSelecting: true` to suppress the
/// actions while selecting.
private struct MobileTaskRowActionsModifier: ViewModifier {
  let task: LorvexTask
  let actions: MobileTaskRowActions
  let isMutating: Bool
  let isBatchSelecting: Bool

  private var isResolved: Bool { task.status.isResolved }

  func body(content: Content) -> some View {
    content
      .swipeActions(edge: .leading, allowsFullSwipe: true) {
        startOrPauseButton
          .tint(LorvexDesign.Palette.accent)
          .disabled(isMutating || isBatchSelecting)
      }
      .swipeActions(edge: .trailing, allowsFullSwipe: true) {
        Button {
          Task { await actions.complete() }
        } label: {
          Label(MobileTaskActionCopy.complete, systemImage: "checkmark.circle")
        }
        .tint(LorvexDesign.Palette.done)
        .disabled(isMutating || isResolved || isBatchSelecting)

        Button {
          Task { await actions.deferByDays(MobileDeferChoice.tomorrow.rawValue) }
        } label: {
          Label(MobileTaskActionCopy.deferTask, systemImage: "clock")
        }
        .tint(LorvexDesign.Palette.dueSoon)
        .disabled(isMutating || isResolved || isBatchSelecting)
      }
      .contextMenu {
        if !isBatchSelecting {
          Button {
            Task { await actions.complete() }
          } label: {
            Label(MobileTaskActionCopy.complete, systemImage: "checkmark.circle")
          }
          .disabled(isMutating || isResolved)

          startOrPauseButton
            .disabled(isMutating)

          MobileDeferMenu(deferByDays: actions.deferByDays) {
            Label(MobileTaskActionCopy.deferTask, systemImage: "clock")
          }
          .disabled(isMutating || isResolved)
        }
      }
  }

  /// Start on an open task, Pause on a started one, nothing otherwise.
  @ViewBuilder
  private var startOrPauseButton: some View {
    if task.status == .open {
      Button {
        Task { await actions.start() }
      } label: {
        Label(MobileTaskActionCopy.start, systemImage: "play.circle")
      }
    } else if task.status == .inProgress {
      Button {
        Task { await actions.pause() }
      } label: {
        Label(MobileTaskActionCopy.pause, systemImage: "pause.circle")
      }
    }
  }
}

extension View {
  /// Attach the shared row actions (``MobileTaskRowActions``) as swipe actions
  /// and a context menu. Pass `isBatchSelecting: true` to disable them and hide
  /// the context menu while the row is in batch-selection mode.
  func taskRowActions(
    task: LorvexTask,
    actions: MobileTaskRowActions,
    isMutating: Bool,
    isBatchSelecting: Bool
  ) -> some View {
    modifier(
      MobileTaskRowActionsModifier(
        task: task, actions: actions, isMutating: isMutating, isBatchSelecting: isBatchSelecting))
  }
}
