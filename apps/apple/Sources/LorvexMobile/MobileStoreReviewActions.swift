import Foundation
import LorvexCore
import SwiftUI

extension MobileStore {
  public var selectedReviewDayIsEditable: Bool {
    selectedReviewDate == logicalTodayString
  }

  public func loadDailyReviewDraft() async {
    reviewDraftLoadToken &+= 1
    let token = reviewDraftLoadToken
    let loadingDate = selectedReviewDate
    isLoadingDailyReviewDraft = true
    do {
      let loadedReview = try await core.loadDailyReview(date: loadingDate)
      let loadedEvidence = try await core.loadDaySummary(date: loadingDate)
      // A newer load owns the flag and the committed data; bail without touching
      // either. Only commit when the selected day still matches what was loaded.
      guard token == reviewDraftLoadToken else { return }
      if selectedReviewDate == loadingDate {
        dailyReview = loadedReview
        dailyReviewDraft = MobileDailyReviewDraft(review: loadedReview)
        dayReviewEvidence = loadedEvidence
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
        withAnimation(.snappy(duration: 0.18)) { dayReviewEvidence = loaded }
      }
    }
    if snapshot.weeklyReview != nil {
      let loadingAnchor = weeklyReviewAnchor
      if let loaded = try? await core.getWeeklyReviewSnapshot(weekOf: loadingAnchor),
        weeklyReviewAnchor == loadingAnchor
      {
        withAnimation(.snappy(duration: 0.18)) { snapshot.weeklyReview = loaded }
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
  @discardableResult
  private func commitDailyReviewDraft(playsFeedback: Bool) async -> Bool {
    // Pin the day being saved: a background refresh can move `selectedReviewDate`
    // across the awaits below, which would otherwise mix the saved day's review
    // with a different day's evidence.
    let savingDate = selectedReviewDate
    isSavingReview = true
    defer { isSavingReview = false }

    do {
      let saved = try await core.upsertDailyReviewPreservingLinks(
        date: savingDate,
        summary: dailyReviewDraft.trimmedSummary,
        mood: dailyReviewDraft.mood,
        energyLevel: dailyReviewDraft.energy,
        wins: dailyReviewDraft.trimmedWins,
        blockers: dailyReviewDraft.trimmedBlockers,
        learnings: dailyReviewDraft.trimmedLearnings
      )
      // Commit the saved day-scoped state before the weekly reload, so a weekly
      // failure can't discard a successful daily save. Guarded on the saved day:
      // a background refresh can move `selectedReviewDate` across these awaits,
      // and if it did the new day's own load owns this state.
      if selectedReviewDate == savingDate {
        dailyReview = saved
        dailyReviewDraft = MobileDailyReviewDraft(review: saved)
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

  public var dailyReviewDraftMatchesLoaded: Bool {
    dailyReviewDraft == MobileDailyReviewDraft(review: dailyReview)
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
}
