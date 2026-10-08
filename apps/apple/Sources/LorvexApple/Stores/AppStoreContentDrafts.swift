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
  /// edits first. Today is selected like any other day, so the day's evidence
  /// moves with the entry.
  func endEditingDailyReview() async {
    await selectReviewDay(logicalTodayDateString)
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
      adoptDayReviewEvidence(try await core.loadDaySummary(date: date), readFor: date)
    } catch {
      await presentUserFacingError(error)
    }
  }

  /// Adopts a day's evidence that was read for `date`, unless the page moved to
  /// another day while the read ran: the selection that moved it loads its own
  /// day, and this older result must not replace it. A `nil` read clears the
  /// evidence.
  func adoptDayReviewEvidence(_ loaded: DayReviewSummary?, readFor date: String) {
    guard selectedReviewDate == date else { return }
    dayReviewEvidence = loaded
  }

  /// Load the daily reviews written in the week the Week scope is viewing for
  /// the read-only digest. The window is the same trailing seven days the weekly
  /// snapshot covers: the six days before `weekOf` through `weekOf` (or today
  /// for the live week). Best-effort: a failed read falls back to empty.
  func loadWeekReviewDigest(weekOf anchor: String?) async {
    let window = weekReviewDigestWindow(weekOf: anchor)
    do {
      weekReviewDigest = try await core.getReviewHistory(
        from: window.from, to: window.to, limit: 7)
    } catch {
      weekReviewDigest = []
      await presentUserFacingError(error)
    }
  }

  /// Re-read the digest of the week being viewed after a change the Week scope
  /// did not start itself: a review saved from the Day scope, or one written by
  /// an assistant or another device that reaches a refresh. A failed read keeps
  /// the entries on screen.
  func reloadWeekReviewDigestKeepingOnFailure() async {
    let window = weekReviewDigestWindow(weekOf: weeklyReviewAnchor)
    if let loaded = try? await core.getReviewHistory(from: window.from, to: window.to, limit: 7) {
      weekReviewDigest = loaded
    }
  }

  /// The seven days a week's digest covers: the six days before the week's last
  /// day, through that day. The last day is `anchor`, or today for the live week.
  private func weekReviewDigestWindow(weekOf anchor: String?) -> (from: String, to: String) {
    let toDay = anchor ?? logicalTodayDateString
    let fromDay = LorvexDateFormatters.ymdUTCAddingDays(toDay, days: -6) ?? toDay
    return (fromDay, toDay)
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

  /// Writes a review typed on the day that is ending to that day, before the
  /// Today snapshot of `newDay` is adopted. A Day scope that follows today reads
  /// the new day as its editor date the moment the snapshot changes, so an
  /// unsaved draft would otherwise be saved onto the new day. A scope showing a
  /// chosen past day is unaffected and needs no write.
  func flushDailyReviewDraftBeforeLogicalDayChange(to newDay: String?) async {
    guard let newDay, newDay != logicalTodayDateString,
      dailyReviewStorage.selectedReviewDate == nil
    else { return }
    await flushDailyReviewDraftIfNeeded()
  }

  /// Loads the editor's day and makes the fields say exactly what it holds. A
  /// later selection owns the editor from the moment it moves it, so a result for
  /// a day the editor already left is dropped.
  private func reloadDailyReviewForEditor() async {
    let date = dailyReviewEditorDate
    await perform {
      let loaded = try await core.loadDailyReview(date: date)
      guard dailyReviewEditorDate == date else { return }
      dailyReview = loaded
      syncDailyReviewDraft()
    }
  }

  /// Saves the editor's fields to the day the editor is on.
  ///
  /// The editor stays live while the write is in flight, so its fields and its
  /// day are read once, before the write starts. The saved entry becomes the
  /// loaded one only if the editor is still on that day. The fields keep the
  /// text the user typed: it already says what the entry holds, and text typed
  /// while the write ran is not in the entry, so it stays an unsaved edit for
  /// the next save.
  func saveDailyReviewDraft() async {
    let savingDate = dailyReviewEditorDate
    let submitted = dailyReviewDraftValues
    await perform {
      let saved = try await core.upsertDailyReviewPreservingLinks(
        date: savingDate,
        summary: submitted.summary.trimmingCharacters(in: .whitespacesAndNewlines),
        mood: submitted.mood,
        energyLevel: submitted.energy,
        wins: submitted.wins.trimmedNilIfEmpty,
        blockers: submitted.blockers.trimmedNilIfEmpty,
        learnings: submitted.learnings.trimmedNilIfEmpty
      )
      if dailyReviewEditorDate == savingDate {
        dailyReview = saved
        if dailyReviewDraftValues == submitted { refreshDailyReviewDraft() }
      }
      weeklyReview = try await core.getWeeklyReviewSnapshot(weekOf: weeklyReviewAnchor)
    }
    await reloadWeekReviewDigestKeepingOnFailure()
  }

  /// True when the daily-review draft fields still match the loaded review —
  /// i.e. there are no unsaved edits. A background `refresh()` (CloudKit push,
  /// command-palette action) uses this to avoid wiping a
  /// review the user is mid-way through typing. Whitespace around a body
  /// section is not an edit: a save trims it away.
  var dailyReviewDraftMatchesLoaded: Bool {
    dailyReviewDraftValues.isStored(as: dailyReview)
  }

  /// Makes the editor's fields say exactly what the loaded review holds
  /// (nothing, for a day with no entry), replacing whatever they hold.
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

  /// Adopts a review that a refresh read for `date`, the editor's day when the
  /// read started. A result for a day the editor has left is dropped: the
  /// selection that moved it loads its own day. The fields follow the review only
  /// if they held no unsaved edits at the moment it is adopted, checked in the
  /// same step, so text typed while the read ran stays in the editor.
  func adoptLoadedDailyReview(_ loaded: DailyReviewEntry?, readFor date: String) {
    guard dailyReviewEditorDate == date else { return }
    let editorHadNoEdits = dailyReviewDraftMatchesLoaded
    dailyReview = loaded
    if editorHadNoEdits { refreshDailyReviewDraft() }
  }

  /// Brings the editor up to date after the loaded review of the day it is
  /// already on was re-read and the editor has no unsaved edits. Fields that
  /// already say what the review holds are left as they are: a save trims the
  /// whitespace around a body section, and replacing the text would delete a
  /// space or a line break the user typed since.
  func refreshDailyReviewDraft() {
    guard !dailyReviewDraftValues.isStored(as: dailyReview) else { return }
    syncDailyReviewDraft()
  }
}
