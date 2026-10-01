import LorvexCore
import SwiftUI

/// Which reflection the Reviews workspace is focused on: the day's calm review
/// page, or the week's digest beside its evidence.
enum ReviewMode: String, CaseIterable, Hashable {
  case daily
  case weekly
}

struct ReviewsWorkspaceView: View {
  @Bindable var store: AppStore
  @State private var mode: ReviewMode = ReviewsWorkspaceView.initialMode
  @State private var dailyReviewEditorFocused = false

  /// The mode the workspace opens in: the day page, unless a DEBUG preview
  /// tour names the week digest in its defaults (`review.workspace.mode`).
  private static var initialMode: ReviewMode {
    #if DEBUG
      if LorvexUIPreview.toursWorkspaces,
        let raw = LorvexUIPreview.previewDefaults.string(forKey: "review.workspace.mode"),
        let mode = ReviewMode(rawValue: raw)
      {
        return mode
      }
    #endif
    return .daily
  }

  var body: some View {
    VStack(spacing: 0) {
      ReviewsWorkspaceHeader()

      Divider()

      // Day scope is one calm reading column; Week scope keeps the digest
      // beside the week's evidence.
      switch mode {
      case .daily:
        DailyReviewForm(
          store: store,
          editingDate: store.dailyReviewEditingDate,
          onReturnToToday: { Task { await store.endEditingDailyReview() } },
          isReadOnly: !store.selectedReviewDayIsEditable,
          onEditorFocusChange: { dailyReviewEditorFocused = $0 }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .weekly:
        WeeklyReviewPage(store: store) { date in
          Task {
            await store.selectReviewDay(date)
            mode = .daily
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .navigationTitle(String(localized: "sidebar.item.reviews", defaultValue: "Review", table: "Localizable", bundle: LorvexL10n.bundle))
    .toolbar {
      ReviewsWorkspaceToolbar(
        store: store,
        state: ReviewsNavigationState(store: store, mode: mode),
        mode: $mode,
        dayStepShortcutsEnabled: !dailyReviewEditorFocused
      )
    }
    .lorvexOpenDestinationActivity(selection: .reviews, isActive: store.selection == .reviews)
    // Load the viewed week's digest when entering Week scope; switching back to
    // Day flushes any pending draft (below).
    .task(id: mode) {
      if mode == .weekly {
        await store.loadWeekReviewDigest(weekOf: store.weeklyReviewAnchor)
      }
    }
    // Autosave: persist the daily draft ~1.2s after the user stops editing, the
    // same model as Notes; the page has no Save button. Each keystroke changes
    // the signature, cancelling the pending sleep (debounce). App quit flushes
    // a draft still inside the debounce.
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
}

