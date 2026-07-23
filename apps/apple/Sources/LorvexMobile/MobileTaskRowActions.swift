import LorvexCore
import SwiftUI

/// The shared Focus / Complete / Defer affordances for a mobile task row:
/// leading (focus) and trailing (complete + defer) swipe actions plus a
/// mirroring context menu. Used by both the plain action row and the
/// batch-selectable workspace row; the latter passes `isBatchSelecting: true`
/// to suppress the actions while selecting.
private struct MobileTaskRowActionsModifier: ViewModifier {
  let task: LorvexTask
  let isFocused: Bool
  let isMutating: Bool
  let isBatchSelecting: Bool
  let toggleFocus: () async -> Void
  let complete: () async -> Void
  let deferTask: () async -> Void
  /// Start (`open → in_progress`); `nil` on surfaces that don't own the action.
  var start: (() async -> Void)? = nil
  /// Mark as Not Started (`in_progress → open`).
  var markNotStarted: (() async -> Void)? = nil

  private var isDone: Bool { task.status.isResolved }
  private var canStart: Bool { task.status == .open && start != nil }
  private var canMarkNotStarted: Bool { task.status == .inProgress && markNotStarted != nil }

  func body(content: Content) -> some View {
    content
      .swipeActions(edge: .leading, allowsFullSwipe: false) {
        Button {
          Task { await toggleFocus() }
        } label: {
          Label(
            isFocused
              ? String(
                localized: "task.unfocus", defaultValue: "Unfocus", table: "Localizable",
                bundle: MobileL10n.bundle)
              : String(
                localized: "action.focus", defaultValue: "Focus", table: "Localizable",
                bundle: MobileL10n.bundle),
            systemImage: isFocused ? "minus.circle" : "scope")
        }
        .tint(.blue)
        .disabled(isMutating || isBatchSelecting)

        if canStart, let start {
          Button {
            Task { await start() }
          } label: {
            Label(
              String(
                localized: "action.start", defaultValue: "Start", table: "Localizable",
                bundle: MobileL10n.bundle), systemImage: "play.circle")
          }
          .tint(.accentColor)
          .disabled(isMutating || isBatchSelecting)
        }
        if canMarkNotStarted, let markNotStarted {
          Button {
            Task { await markNotStarted() }
          } label: {
            Label(
              String(
                localized: "action.mark_not_started", defaultValue: "Not Started",
                table: "Localizable", bundle: MobileL10n.bundle),
              systemImage: "pause.circle")
          }
          .tint(.accentColor)
          .disabled(isMutating || isBatchSelecting)
        }
      }
      .swipeActions(edge: .trailing, allowsFullSwipe: true) {
        Button {
          Task { await complete() }
        } label: {
          Label(
            String(
              localized: "action.complete", defaultValue: "Complete", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "checkmark.circle")
        }
        .tint(.green)
        .disabled(isMutating || isDone || isBatchSelecting)

        Button {
          Task { await deferTask() }
        } label: {
          Label(
            String(
              localized: "action.defer", defaultValue: "Defer", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "clock")
        }
        .tint(.orange)
        .disabled(isMutating || isDone || isBatchSelecting)
      }
      .contextMenu {
        if !isBatchSelecting {
          Button {
            Task { await complete() }
          } label: {
            Label(
              String(
                localized: "action.complete", defaultValue: "Complete", table: "Localizable",
                bundle: MobileL10n.bundle), systemImage: "checkmark.circle")
          }
          .disabled(isMutating || isDone)

          if canStart, let start {
            Button {
              Task { await start() }
            } label: {
              Label(
                String(
                  localized: "action.start", defaultValue: "Start", table: "Localizable",
                  bundle: MobileL10n.bundle), systemImage: "play.circle")
            }
            .disabled(isMutating)
          }
          if canMarkNotStarted, let markNotStarted {
            Button {
              Task { await markNotStarted() }
            } label: {
              Label(
                String(
                  localized: "task.action.mark_not_started", defaultValue: "Mark as Not Started",
                  table: "Localizable", bundle: MobileL10n.bundle),
                systemImage: "pause.circle")
            }
            .disabled(isMutating)
          }

          Button {
            Task { await deferTask() }
          } label: {
            Label(
              String(
                localized: "action.defer", defaultValue: "Defer", table: "Localizable",
                bundle: MobileL10n.bundle), systemImage: "clock")
          }
          .disabled(isMutating || isDone)

          Button {
            Task { await toggleFocus() }
          } label: {
            Label(
              isFocused
                ? String(
                  localized: "task.unfocus", defaultValue: "Unfocus", table: "Localizable",
                  bundle: MobileL10n.bundle)
                : String(
                  localized: "action.focus", defaultValue: "Focus", table: "Localizable",
                  bundle: MobileL10n.bundle),
              systemImage: isFocused ? "minus.circle" : "scope")
          }
          .disabled(isMutating)
        }
      }
  }
}

extension View {
  /// Attach the shared Focus / Complete / Defer swipe actions and context menu
  /// to a task row. Pass `isBatchSelecting: true` to disable them (and hide the
  /// context menu) while the row is in batch-selection mode.
  func taskRowActions(
    task: LorvexTask,
    isFocused: Bool,
    isMutating: Bool,
    isBatchSelecting: Bool,
    toggleFocus: @escaping () async -> Void,
    complete: @escaping () async -> Void,
    deferTask: @escaping () async -> Void,
    start: (() async -> Void)? = nil,
    markNotStarted: (() async -> Void)? = nil
  ) -> some View {
    modifier(
      MobileTaskRowActionsModifier(
        task: task,
        isFocused: isFocused,
        isMutating: isMutating,
        isBatchSelecting: isBatchSelecting,
        toggleFocus: toggleFocus,
        complete: complete,
        deferTask: deferTask,
        start: start,
        markNotStarted: markNotStarted))
  }
}
