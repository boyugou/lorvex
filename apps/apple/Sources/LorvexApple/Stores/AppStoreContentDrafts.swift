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

  func dailyReviewIsEditable(date: String) -> Bool {
    DailyReviewEntry.canEdit(on: date, today: logicalTodayDateString)
  }

  /// Anchor the daily editor to a past day inside the write window and load
  /// that day's entry into the drafts. No-op for dates the core would reject.
  /// Flushes the current day's unsaved edits first so switching days never
  /// silently drops them; when that write fails the editor stays on its day with
  /// the text intact and the error shown.
  @discardableResult
  func beginEditingDailyReview(date: String) async -> Bool {
    guard dailyReviewIsEditable(date: date) else { return false }
    return await openReviewEntry(date: date)
  }

  /// Return the editor to today's entry, flushing the current day's unsaved
  /// edits first. Today is selected like any other day, so the day's evidence
  /// moves with the entry.
  func endEditingDailyReview() async {
    await selectReviewDay(logicalTodayDateString)
  }

  /// Opens the entry and its evidence for the chosen date. Older entries use
  /// the same navigation and stay outside the interactive write window.
  func selectReviewDay(_ date: String) async {
    guard await openReviewEntry(date: date) else { return }
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

  /// Writes the editor's unsaved edits before it moves to another day. False when
  /// they are still unsaved afterwards, because the write failed: the editor then
  /// stays on its day instead of reloading over text that was never saved.
  private func settleDailyReviewDraftBeforeMoving() async -> Bool {
    await flushDailyReviewDraftIfNeeded()
    return dailyReviewDraftMatchesLoaded
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

  /// Keep the old editor on its own day while the destination is being read.
  /// Switching the date and its draft together prevents text typed during a
  /// slow read from landing on the destination or disappearing on arrival.
  private func openReviewEntry(date: String) async -> Bool {
    dailyReviewStorage.selectionRequest &+= 1
    let request = dailyReviewStorage.selectionRequest
    let sourceDay = selectedReviewDate
    let entryBeforeRead = dailyReview
    do {
      let loaded = try await core.loadDailyReview(date: date)
      guard dailyReviewStorage.selectionRequest == request, selectedReviewDate == sourceDay else { return false }
      if date == sourceDay {
        // A peer update or an autosave may have advanced this entry during the read.
        if dailyReview == entryBeforeRead { adoptLoadedDailyReview(loaded, readFor: date) }
        return await settleDailyReviewDraftBeforeMoving()
      }
      guard await settleDailyReviewDraftBeforeMoving(),
        dailyReviewStorage.selectionRequest == request, selectedReviewDate == sourceDay
      else { return false }
      dailyReviewEditingDate = dailyReviewIsEditable(date: date) && date != logicalTodayDateString ? date : nil
      selectedReviewDate = date
      dailyReview = loaded
      syncDailyReviewDraft()
      return true
    } catch {
      if dailyReviewStorage.selectionRequest == request { await presentUserFacingError(error) }
      return false
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
    let base = DailyReviewDraftValues(review: dailyReview)
    await perform {
      let saved = try await core.saveDailyReviewEdits(date: savingDate, base: base, draft: submitted)
      if dailyReviewEditorDate == savingDate {
        dailyReview = saved
        dailyReviewDraftValues = dailyReviewDraftValues.rebased(from: submitted, onto: .init(review: saved))
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
    dailyReviewDraftValues = .init(review: dailyReview)
  }

  /// Adopts a review that a refresh read for `date`, the editor's day when the
  /// read started. A result for a day the editor has left is dropped: the
  /// selection that moved it loads its own day. Untouched fields follow the
  /// incoming review and the Mac field being edited keeps the user's text.
  func adoptLoadedDailyReview(_ loaded: DailyReviewEntry?, readFor date: String) {
    guard dailyReviewEditorDate == date else { return }
    let base = DailyReviewDraftValues(review: dailyReview)
    dailyReview = loaded
    dailyReviewDraftValues = dailyReviewDraftValues.rebased(from: base, onto: .init(review: loaded))
  }
}
