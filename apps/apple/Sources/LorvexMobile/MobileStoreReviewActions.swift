import Foundation
import LorvexCore
import SwiftUI

extension MobileStore {
  public var selectedReviewDayIsEditable: Bool {
    selectedReviewDate == logicalTodayString
  }

  /// Loads the selected day's review and evidence for the page. A day the page
  /// has nothing for yet shows the loading state until its read commits, and the
  /// fields then take exactly what the review holds. A reload of the day the page
  /// already shows, as when the Review tab is entered again, keeps the fields on
  /// screen and adopts the read the way a refresh does: no loading skeleton, the
  /// scroll position survives, and text typed during the read stays. A newer
  /// load supersedes an older one.
  public func loadDailyReviewDraft() async {
    reviewDraftLoadToken &+= 1
    let token = reviewDraftLoadToken
    let loadingDate = selectedReviewDate
    let reloadsShownDay = !isLoadingDailyReviewDraft && reviewDraftDate == loadingDate
    if !reloadsShownDay { isLoadingDailyReviewDraft = true }
    do {
      let loadedReview = try await core.loadDailyReview(date: loadingDate)
      let loadedEvidence = try await core.loadDaySummary(date: loadingDate)
      // A newer load owns the flag and the committed data; bail without touching
      // either. Only commit when the selected day still matches what was loaded.
      guard token == reviewDraftLoadToken else { return }
      if selectedReviewDate == loadingDate {
        if reloadsShownDay {
          adoptLoadedDailyReview(loadedReview, readFor: loadingDate)
        } else {
          dailyReview = loadedReview
          dailyReviewDraft = MobileDailyReviewDraft(review: loadedReview)
        }
        dayReviewEvidence = loadedEvidence
        reviewDraftDate = loadingDate
        errorMessage = nil
      }
    } catch {
      guard token == reviewDraftLoadToken else { return }
      if selectedReviewDate == loadingDate {
        await presentUserFacingError(error)
      }
    }
    // Reset the flag for the latest load regardless of whether the day still
    // matches: `selectedReviewDate` can be moved by a background refresh that
    // spawns no load, so gating the reset on the date would strand it `true`.
    if token == reviewDraftLoadToken {
      isLoadingDailyReviewDraft = false
    }
  }

  /// Re-read the review's task lists once a task changed: the day's done and
  /// still-open tasks and the week's overdue and pushed ones, so both review
  /// pages follow a change made anywhere, their own rows included. A list the
  /// review has not loaded yet stays unloaded; a read that fails, or lands
  /// after the review moved to another day or week, keeps what is shown.
  func reloadReviewEvidenceAfterTaskMutation() async {
    if dayReviewEvidence != nil {
      let loadingDate = selectedReviewDate
      if let loaded = try? await core.loadDaySummary(date: loadingDate),
        selectedReviewDate == loadingDate
      {
        lorvexAnimated(.snappy(duration: 0.18)) { dayReviewEvidence = loaded }
      }
    }
    if snapshot.weeklyReview != nil {
      let loadingAnchor = weeklyReviewAnchor
      if let loaded = try? await core.getWeeklyReviewSnapshot(weekOf: loadingAnchor),
        weeklyReviewAnchor == loadingAnchor
      {
        lorvexAnimated(.snappy(duration: 0.18)) { snapshot.weeklyReview = loaded }
      }
    }
  }

  public func selectReviewDay(_ date: String) async {
    // Flush best-effort, never blocking navigation on it: a body-only edit
    // (mood / energy / wins / blockers / learnings with no summary) is a valid,
    // savable review, so it must not trap the user on the current day.
    await flushDailyReviewDraftIfNeeded()
    selectedReviewDate = date
    await loadDailyReviewDraft()
  }

  public func returnReviewToToday() async {
    await selectReviewDay(logicalTodayString)
  }

  /// Moves the Day review to `newDay` when it was showing `previousDay`, the
  /// logical day that has just ended, so a phone that kept the app alive
  /// overnight opens the review on today instead of on a read-only yesterday.
  /// Text typed on the ended day and not yet saved is written to that day first,
  /// while it is still editable; if that write fails the review stays on its
  /// day with the text intact. A review the user opened on another day stays
  /// there. Call it before the Today snapshot of `newDay` replaces the previous
  /// one, which is what makes the ended day stop being editable.
  func carryReviewToNewLogicalDay(from previousDay: String, to newDay: String) async {
    guard selectedReviewDate == previousDay, newDay > previousDay else { return }
    await flushDailyReviewDraftIfNeeded()
    guard dailyReviewDraftMatchesLoaded else { return }
    selectedReviewDate = newDay
  }

  public func loadWeekReviewDigest(weekOf anchor: String?) async {
    let toDay = anchor ?? logicalTodayString
    let fromDay = LorvexDateFormatters.ymdUTCAddingDays(toDay, days: -6) ?? toDay
    do {
      weekReviewDigest = try await core.getReviewHistory(from: fromDay, to: toDay, limit: 7)
      errorMessage = nil
    } catch {
      weekReviewDigest = []
      await presentUserFacingError(error)
    }
  }

  /// Explicit Save: requires a non-empty summary and valid ratings (the manual
  /// save rule), then commits. Body-only edits reach the store only through the
  /// non-blocking ``flushDailyReviewDraftIfNeeded()`` auto-flush.
  @discardableResult
  public func saveDailyReviewDraft() async -> Bool {
    guard selectedReviewDayIsEditable, dailyReviewDraft.canSave, !isSavingReview,
      !isLoadingDailyReviewDraft
    else {
      return false
    }
    return await commitDailyReviewDraft(playsFeedback: true)
  }

  /// Upsert the current draft for the selected day. Callers gate editability /
  /// in-flight state; this performs the write, pins the day across its awaits,
  /// and commits day-scoped state only if the day hasn't moved. `playsFeedback`
  /// is on for an explicit Save, off for a silent auto-flush.
  ///
  /// The fields stay live while the write is in flight, so they are read once,
  /// before it starts. They keep the text the user typed: it already says what
  /// the saved entry holds, and text typed while the write ran is not in the
  /// entry, so it stays an unsaved edit for the next save.
  @discardableResult
  private func commitDailyReviewDraft(playsFeedback: Bool) async -> Bool {
    // Pin the day being saved: a background refresh can move `selectedReviewDate`
    // across the awaits below, which would otherwise mix the saved day's review
    // with a different day's evidence.
    let savingDate = selectedReviewDate
    let submitted = dailyReviewDraft
    isSavingReview = true
    defer { isSavingReview = false }

    do {
      let saved = try await core.upsertDailyReviewPreservingLinks(
        date: savingDate,
        summary: submitted.trimmedSummary,
        mood: submitted.mood,
        energyLevel: submitted.energy,
        wins: submitted.trimmedWins,
        blockers: submitted.trimmedBlockers,
        learnings: submitted.trimmedLearnings
      )
      // Commit the saved day-scoped state before the weekly reload, so a weekly
      // failure can't discard a successful daily save. Guarded on the saved day:
      // a background refresh can move `selectedReviewDate` across these awaits,
      // and if it did the new day's own load owns this state.
      if selectedReviewDate == savingDate {
        dailyReview = saved
        if dailyReviewDraft == submitted { refreshDailyReviewDraft() }
        dayReviewEvidence = try await core.loadDaySummary(date: savingDate)
      }
      // Week-scoped state is day-independent and always adopts the latest values.
      snapshot.weeklyReview = try await core.getWeeklyReviewSnapshot(weekOf: weeklyReviewAnchor)
      await loadWeekReviewDigest(weekOf: weeklyReviewAnchor)
      errorMessage = nil
      if playsFeedback { feedbackProvider.playFeedback(.contentSaved) }
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  /// The week review's decision: park a task that keeps getting pushed in
  /// Someday. The task mutation's review reload then drops it from the
  /// viewed week's pushed list.
  public func parkReviewTaskInSomeday(_ id: LorvexTask.ID) async {
    await markTaskSomeday(id)
  }

  /// True when the daily-review fields hold no unsaved edit: saving them would
  /// leave the loaded review as it is. Whitespace around a section is not an
  /// edit, since a save trims it away.
  public var dailyReviewDraftMatchesLoaded: Bool {
    dailyReviewDraft.isStored(as: dailyReview)
  }

  /// Adopts a review that a refresh read for `date`, the review's day when the
  /// read started. A result for a day the review has left is dropped: the
  /// selection that moved it loads its own day. The fields follow the review only
  /// if they held no unsaved edit at the moment it is adopted, checked in the
  /// same step, so text typed while the read ran stays in the editor.
  func adoptLoadedDailyReview(_ loaded: DailyReviewEntry?, readFor date: String) {
    guard selectedReviewDate == date else { return }
    let editorHadNoEdits = dailyReviewDraftMatchesLoaded
    dailyReview = loaded
    if editorHadNoEdits { refreshDailyReviewDraft() }
  }

  /// Adopts a day's evidence that was read for `date`, unless the review moved to
  /// another day while the read ran: the selection that moved it loads its own
  /// day, and this older result must not replace it. A `nil` read clears the
  /// evidence.
  func adoptDayReviewEvidence(_ loaded: DayReviewSummary?, readFor date: String) {
    guard selectedReviewDate == date else { return }
    dayReviewEvidence = loaded
  }

  /// Brings the fields up to date after the loaded review of the day the page is
  /// already on was re-read and the fields hold no unsaved edit. Fields that
  /// already say what the review holds are left as they are: a save trims the
  /// whitespace around a section, and replacing the text would delete a space or
  /// a line break the user typed since.
  func refreshDailyReviewDraft() {
    guard !dailyReviewDraft.isStored(as: dailyReview) else { return }
    dailyReviewDraft = MobileDailyReviewDraft(review: dailyReview)
  }

  /// Persist the draft when it differs from the loaded entry, regardless of
  /// whether a summary was written — the core accepts a summary-less review, so a
  /// body-only edit (mood / energy / wins / blockers / learnings) must not be
  /// lost when the editor switches day or view. Best-effort and non-blocking:
  /// only an editable day is written, and callers never gate navigation on it.
  public func flushDailyReviewDraftIfNeeded() async {
    guard !dailyReviewDraftMatchesLoaded, selectedReviewDayIsEditable,
      !isSavingReview, !isLoadingDailyReviewDraft
    else { return }
    _ = await commitDailyReviewDraft(playsFeedback: false)
  }

  /// Writes the drafts that save on their own, as the app leaves the foreground.
  /// The daily review saves when a field loses focus, its mood or energy
  /// changes, or its page disappears; moving the app to the background does none
  /// of these, and iOS can end a suspended process without further notice, so
  /// text typed in the last field would be lost. Runs before the sync pass of
  /// the same background window, which then sends the saved entry to the
  /// other devices.
  public func flushAutosaveDraftsBeforeSuspension() async {
    await flushDailyReviewDraftIfNeeded()
  }
}
