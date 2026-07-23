import Foundation
import LorvexCore

extension AppStore {
  /// The day the daily editor reads and writes. Mirrors the strip's
  /// ``selectedReviewDate``: an editable day shows in the editor and is the
  /// autosave write target, while a read-only past day is loaded for display
  /// from this same day (`dailyReviewEditingDate` stays `nil` so the autosave
  /// never arms).
  var dailyReviewEditorDate: String {
    selectedReviewDate
  }

  /// Days back from today the editor may anchor — the interactive write
  /// window enforced by the core (`DailyReviewDate.maxStalenessDays`).
  static let dailyReviewEditableWindowDays = 7

  /// True when `date` may be loaded into the editor for changes: today, or a
  /// past day still inside the write window.
  func dailyReviewIsEditable(date: String) -> Bool {
    let today = logicalTodayDateString
    guard date <= today else { return false }
    guard
      let floor = LorvexDateFormatters.ymdUTCAddingDays(
        today, days: -Self.dailyReviewEditableWindowDays)
    else { return false }
    return date >= floor
  }

  /// Anchor the daily editor to a past day inside the write window and load
  /// that day's entry into the drafts. No-op for dates the core would reject.
  /// Flushes the current day's unsaved edits first so switching days never
  /// silently drops them.
  func beginEditingDailyReview(date: String) async {
    guard dailyReviewIsEditable(date: date) else { return }
    await flushDailyReviewDraftIfNeeded()
    let today = logicalTodayDateString
    dailyReviewEditingDate = date == today ? nil : date
    selectedReviewDate = date
    await reloadDailyReviewForEditor()
  }

  /// Return the editor to today's entry, flushing the current day's unsaved
  /// edits first.
  func endEditingDailyReview() async {
    await flushDailyReviewDraftIfNeeded()
    dailyReviewEditingDate = nil
    selectedReviewDate = logicalTodayDateString
    await reloadDailyReviewForEditor()
  }

  /// The date strip's unified day selection. Editable days (today or inside the
  /// write window) open in the daily editor via ``beginEditingDailyReview``; an
  /// older day loads its saved review read-only — `dailyReview` is populated for
  /// display while `dailyReviewEditingDate` stays `nil` so the autosave never
  /// arms on a day the core would reject. Either way the day's objective
  /// evidence is reloaded for the right-hand panel.
  func selectReviewDay(_ date: String) async {
    if dailyReviewIsEditable(date: date) {
      await beginEditingDailyReview(date: date)
    } else {
      await flushDailyReviewDraftIfNeeded()
      dailyReviewEditingDate = nil
      selectedReviewDate = date
      await reloadDailyReviewForEditor()
    }
    await loadDayReviewEvidence(date: date)
  }

  /// True when the Day scope is showing today, gating the nav's "Today" button.
  var isViewingCurrentDay: Bool {
    selectedReviewDate == logicalTodayDateString
  }

  /// Step the Day-scope selection by whole days from the currently selected day.
  /// A no-op when the adjacent day can't be derived. Routes through
  /// ``selectReviewDay`` so the editable/read-only gating and evidence reload
  /// match a direct pick.
  func stepReviewDay(by days: Int) async {
    guard let shifted = LorvexDateFormatters.ymdUTCAddingDays(selectedReviewDate, days: days)
    else { return }
    await selectReviewDay(shifted)
  }

  /// Load the objective day evidence (completed / unfinished / habits / events /
  /// created) for the right-hand panel. Best-effort: a failed read leaves the
  /// previous evidence in place rather than aborting selection.
  func loadDayReviewEvidence(date: String) async {
    do {
      dayReviewEvidence = try await core.loadDaySummary(date: date)
    } catch {
      await presentUserFacingError(error)
    }
  }

  /// Load the daily reviews written in the week the Week scope is viewing for
  /// the read-only digest. The window is the same trailing seven days the weekly
  /// snapshot covers: the six days before `weekOf` through `weekOf` (or today
  /// for the live week). Best-effort: a failed read falls back to empty.
  func loadWeekReviewDigest(weekOf anchor: String?) async {
    let toDay = anchor ?? logicalTodayDateString
    let fromDay = LorvexDateFormatters.ymdUTCAddingDays(toDay, days: -6) ?? toDay
    do {
      weekReviewDigest = try await core.getReviewHistory(from: fromDay, to: toDay, limit: 7)
    } catch {
      weekReviewDigest = []
      await presentUserFacingError(error)
    }
  }

  /// Persist the daily-review draft when it differs from the loaded entry,
  /// regardless of whether a summary was written. The core accepts a
  /// summary-less review, so body-only edits (wins / blockers / learnings /
  /// mood / energy) must not be lost when the editor switches day, switches to
  /// the weekly view, or the workspace disappears.
  func flushDailyReviewDraftIfNeeded() async {
    guard !dailyReviewDraftMatchesLoaded else { return }
    await saveDailyReviewDraft()
  }

  private func reloadDailyReviewForEditor() async {
    await perform {
      dailyReview = try await core.loadDailyReview(date: dailyReviewEditorDate)
      syncDailyReviewDraft()
    }
  }

  func saveDailyReviewDraft() async {
    await perform {
      dailyReview = try await core.upsertDailyReviewPreservingLinks(
        date: dailyReviewEditorDate,
        summary: dailyReviewSummaryDraft,
        mood: dailyReviewMood,
        energyLevel: dailyReviewEnergy,
        wins: dailyReviewWinsDraft.trimmedNilIfEmpty,
        blockers: dailyReviewBlockersDraft.trimmedNilIfEmpty,
        learnings: dailyReviewLearningsDraft.trimmedNilIfEmpty
      )
      syncDailyReviewDraft()
      weeklyReview = try await core.loadWeeklyReview()
    }
  }

  /// True when the daily-review draft fields still match the loaded review —
  /// i.e. there are no unsaved edits. A background `refresh()` (CloudKit push,
  /// command-palette action) uses this to avoid wiping a
  /// review the user is mid-way through typing.
  var dailyReviewDraftMatchesLoaded: Bool {
    dailyReviewSummaryDraft == (dailyReview?.summary ?? "")
      && dailyReviewWinsDraft == (dailyReview?.wins ?? "")
      && dailyReviewBlockersDraft == (dailyReview?.blockers ?? "")
      && dailyReviewLearningsDraft == (dailyReview?.learnings ?? "")
      && dailyReviewMood == dailyReview?.mood
      && dailyReviewEnergy == dailyReview?.energyLevel
  }

  func syncDailyReviewDraft() {
    guard let dailyReview else {
      dailyReviewSummaryDraft = ""
      dailyReviewWinsDraft = ""
      dailyReviewBlockersDraft = ""
      dailyReviewLearningsDraft = ""
      dailyReviewMood = nil
      dailyReviewEnergy = nil
      return
    }
    dailyReviewSummaryDraft = dailyReview.summary
    dailyReviewWinsDraft = dailyReview.wins ?? ""
    dailyReviewBlockersDraft = dailyReview.blockers ?? ""
    dailyReviewLearningsDraft = dailyReview.learnings ?? ""
    dailyReviewMood = dailyReview.mood
    dailyReviewEnergy = dailyReview.energyLevel
  }
}
