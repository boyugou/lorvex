import LorvexCore
import SwiftUI

struct MobileTaskActionSection: View {
  let task: LorvexTask
  let isFocused: Bool
  let isMutating: Bool
  let toggleFocus: () async -> Void
  let complete: () async -> Void
  let reopen: () async -> Void
  let deferTask: () async -> Void
  let markSomeday: () async -> Void
  let editRecurrence: () -> Void
  let cancel: () async -> Void
  /// Start (`open → in_progress`) / Mark as Not Started (`in_progress → open`).
  var start: (() async -> Void)? = nil
  var markNotStarted: (() async -> Void)? = nil

  var body: some View {
    Section {
      focusButton
      completeButton
      startButton
      deferButton
      somedayButton
      recurrenceButton
      reopenButton
      cancelButton
    }
  }

  // Put the "In Progress" marker on an open task, or take it off a started one.
  // Title tracks the state, mirroring the macOS detail action and context menu.
  @ViewBuilder
  private var startButton: some View {
    if task.status == .open, let start {
      Button {
        Task { await start() }
      } label: {
        Label(
          String(
            localized: "action.start", defaultValue: "Start", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "play.circle")
      }
      .disabled(isMutating)
      .accessibilityIdentifier("task.detail.start")
    } else if task.status == .inProgress, let markNotStarted {
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
      .accessibilityIdentifier("task.detail.markNotStarted")
    }
  }

  private var focusButton: some View {
    Button {
      Task { await toggleFocus() }
    } label: {
      Label(
        isFocused
          ? String(
            localized: "action.remove_from_focus", defaultValue: "Remove from Focus",
            table: "Localizable", bundle: MobileL10n.bundle)
          : String(
            localized: "action.focus", defaultValue: "Focus", table: "Localizable",
            bundle: MobileL10n.bundle),
        systemImage: isFocused ? "minus.circle" : "scope"
      )
    }
    .disabled(isMutating)
  }

  private var completeButton: some View {
    Button {
      Task { await complete() }
    } label: {
      Label(
        String(
          localized: "action.complete", defaultValue: "Complete", table: "Localizable",
          bundle: MobileL10n.bundle), systemImage: "checkmark.circle")
    }
    .disabled(isMutating || !canComplete)
  }

  // Mobile defer is intentionally a single direct "Defer to Tomorrow" tap — the
  // macOS surfaces offer a day-choice menu (TaskDeferMenu: Tomorrow / In 3 days /
  // Next Week), but a one-tap action fits the phone's quick-triage flow. The
  // glyph matches macOS so the concept reads the same across surfaces.
  private var deferButton: some View {
    Button {
      Task { await deferTask() }
    } label: {
      Label(
        String(
          localized: "action.defer_to_tomorrow", defaultValue: "Defer to Tomorrow",
          table: "Localizable", bundle: MobileL10n.bundle),
        systemImage: "clock.arrow.circlepath")
    }
    .disabled(isMutating || !canComplete)
  }

  // Park an open task for later. Someday is a live (unresolved) status, so it
  // sits alongside Defer rather than in the terminal actions — and only an open
  // task can be parked (a resolved or already-parked task shows nothing here).
  @ViewBuilder
  private var somedayButton: some View {
    if task.status == .open {
      Button {
        Task { await markSomeday() }
      } label: {
        Label(
          String(
            localized: "action.move_to_someday", defaultValue: "Move to Someday",
            table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: "moon")
      }
      .disabled(isMutating)
      .accessibilityIdentifier("task.detail.moveToSomeday")
    }
  }

  private var recurrenceButton: some View {
    Button {
      editRecurrence()
    } label: {
      HStack {
        Label(
          task.recurrence == nil
            ? String(
              localized: "action.repeat", defaultValue: "Repeat", table: "Localizable",
              bundle: MobileL10n.bundle)
            : String(
              localized: "action.edit_repeat", defaultValue: "Edit Repeat", table: "Localizable",
              bundle: MobileL10n.bundle),
          systemImage: "repeat"
        )
        if let recurrence = task.recurrence {
          Spacer()
          Text(recurrence.displaySummary(exceptions: task.recurrenceExceptions))
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
    .disabled(isMutating)
  }

  // Return a resolved OR parked task to the open list. A someday task reads as
  // "Move to Open" (it was never finished, only parked), a completed/cancelled
  // task as "Reopen" — both drive the same reopen transition, matching macOS.
  @ViewBuilder
  private var reopenButton: some View {
    if task.status == .someday {
      Button {
        Task { await reopen() }
      } label: {
        Label(
          String(
            localized: "action.move_to_open", defaultValue: "Move to Open", table: "Localizable",
            bundle: MobileL10n.bundle),
          systemImage: "arrow.up.circle")
      }
      .disabled(isMutating)
      .accessibilityIdentifier("task.detail.moveToOpen")
    } else if canReopen {
      Button {
        Task { await reopen() }
      } label: {
        Label(
          String(
            localized: "action.reopen", defaultValue: "Reopen", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "arrow.counterclockwise")
      }
      .disabled(isMutating)
      .accessibilityIdentifier("task.detail.reopen")
    }
  }

  private var cancelButton: some View {
    Button(role: .destructive) {
      Task { await cancel() }
    } label: {
      Label(
        String(
          localized: "action.cancel_task", defaultValue: "Cancel", table: "Localizable",
          bundle: MobileL10n.bundle), systemImage: "xmark.circle")
    }
    .disabled(isMutating || !canCancel)
  }

  private var canComplete: Bool {
    task.status.isActive
  }

  private var canCancel: Bool {
    task.status.isActive
  }

  private var canReopen: Bool {
    task.status.isResolved
  }
}
