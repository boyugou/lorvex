import LorvexCore
import SwiftUI
import TipKit

/// Which reflection the Reviews workspace is focused on. The daily entry and the
/// weekly digest share one three-zone scaffold (header + date navigation +
/// two-column body); the scope toggle swaps the contents of the two columns.
enum ReviewMode: String, CaseIterable, Hashable {
  case daily
  case weekly
}

struct ReviewsWorkspaceView: View {
  @Bindable var store: AppStore
  @State private var mode: ReviewMode = .daily
  @State private var dailyReviewEditorFocused = false
  private let dailyReviewTip = DailyReviewTip()

  var body: some View {
    VStack(spacing: 0) {
      ReviewsWorkspaceNavigationBar(
        store: store,
        mode: $mode,
        dayStepShortcutsEnabled: !dailyReviewEditorFocused
      )

      Divider()

      // Body shares the header's reading lane so the reflection column's left
      // edge lines up with the workspace title (and with the other workspaces'
      // content), instead of spanning the full width while the lane-centered
      // title sits indented above it.
      WorkspaceReviewLane {
        HStack(spacing: 0) {
          reflectionColumn
            .frame(maxWidth: .infinity, maxHeight: .infinity)

          Divider()

          ReviewEvidencePanel(content: evidenceContent)
            .frame(width: ReviewsWorkspaceLayout.evidenceWidth)
        }
        .frame(maxHeight: .infinity)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.background)
    }
    .navigationTitle(String(localized: "sidebar.item.reviews", defaultValue: "Reviews", table: "Localizable", bundle: LorvexL10n.bundle))
    .lorvexOpenDestinationActivity(selection: .reviews, isActive: store.selection == .reviews)
    .popoverTip(dailyReviewTip)
    // Load the viewed week's digest when entering Week scope; switching back to
    // Day flushes any pending draft (below).
    .task(id: mode) {
      if mode == .weekly {
        await store.loadWeekReviewDigest(weekOf: store.weeklyReviewAnchor)
      }
    }
    // Autosave: persist the daily draft ~1.2s after the user stops editing, the
    // same model as Notes — the footer button stays as the explicit confirm,
    // but a finished entry should never be lost to a missed click. Each
    // keystroke changes the signature, cancelling the pending sleep (debounce).
    .task(id: dailyReviewDraftSignature) {
      // Autosave ANY unsaved edit (body-only included) — the core accepts a
      // summary-less review, so the old "needs a summary" gate dropped wins /
      // blockers / learnings on a switch. Never arms on a read-only past day.
      guard mode == .daily, store.selectedReviewDayIsEditable,
        !store.dailyReviewDraftMatchesLoaded
      else { return }
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      guard !Task.isCancelled else { return }
      await store.saveDailyReviewDraft()
    }
    // The debounce above is cancelled when leaving the daily editor; flush the
    // pending draft on those exits so nothing is lost mid-edit.
    .onChange(of: mode) { _, newMode in
      if newMode != .daily {
        dailyReviewEditorFocused = false
        Task { await store.flushDailyReviewDraftIfNeeded() }
      }
    }
    .onDisappear {
      dailyReviewEditorFocused = false
      Task { await store.flushDailyReviewDraftIfNeeded() }
    }
  }

  @ViewBuilder
  private var reflectionColumn: some View {
    switch mode {
    case .daily:
      DailyReviewForm(
        store: store,
        scrollsInternally: true,
        saveState: dailyReviewSaveState,
        // The footer's explicit "commit now" — kept because app-quit within the
        // autosave debounce isn't otherwise flushed. It routes through the same
        // guarded flush as every autosave exit, so a click racing a just-fired
        // autosave is a no-op (no duplicate write / changelog row) rather than a
        // second save fighting the first.
        onSave: { Task { await store.flushDailyReviewDraftIfNeeded() } },
        editingDate: store.dailyReviewEditingDate,
        onReturnToToday: { Task { await store.endEditingDailyReview() } },
        isReadOnly: !store.selectedReviewDayIsEditable,
        onEditorFocusChange: { dailyReviewEditorFocused = $0 }
      )
    case .weekly:
      WeekReviewDigest(
        reviews: store.weekReviewDigest,
        onSelectDay: { date in
          Task {
            await store.selectReviewDay(date)
            mode = .daily
          }
        }
      )
    }
  }

  private var evidenceContent: ReviewEvidencePanel.Content {
    switch mode {
    case .daily: .day(store.dayReviewEvidence)
    case .weekly: .week(store.weeklyReview)
    }
  }

  /// One value that changes with any edit to the daily draft, driving the
  /// autosave debounce.
  private var dailyReviewDraftSignature: String {
    [
      store.dailyReviewSummaryDraft,
      store.dailyReviewWinsDraft,
      store.dailyReviewBlockersDraft,
      store.dailyReviewLearningsDraft,
      String(describing: store.dailyReviewMood),
      String(describing: store.dailyReviewEnergy),
      mode.rawValue,
      // Anchor switches must cancel a pending autosave — never write the old
      // day's half-typed text onto the newly opened day.
      store.dailyReviewEditorDate,
    ].joined(separator: "\u{1F}")
  }

  /// Drives the footer status + Save affordance from saved-vs-unsaved state, not
  /// summary presence. The core accepts a summary-less review and the autosave
  /// persists any unsaved edit, so body-only edits (wins / blockers / learnings
  /// / mood / energy) are `.unsaved` work to persist — never gated behind a
  /// missing summary. `.needsSummary` now means only "empty draft, nothing
  /// saved yet," so the footer's enabled state matches what autosave actually does.
  private var dailyReviewSaveState: DailyReviewSaveState {
    if !store.dailyReviewDraftMatchesLoaded { return .unsaved }
    return store.dailyReview != nil ? .saved : .needsSummary
  }
}

private enum ReviewsWorkspaceLayout {
  /// The fixed width of the right-hand evidence panel; the reflection column
  /// takes the remaining width.
  static let evidenceWidth: CGFloat = 300
}
