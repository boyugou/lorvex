import Foundation
import LorvexCore

extension MobileStore {
  public var selectedReviewDayIsEditable: Bool {
    selectedReviewDate == logicalTodayString
  }

  public func loadDailyReviewDraft() async {
    let loadingDate = selectedReviewDate
    isLoadingDailyReviewDraft = true
    do {
      let loadedReview = try await core.loadDailyReview(date: loadingDate)
      let loadedEvidence = try await core.loadDaySummary(date: loadingDate)
      guard selectedReviewDate == loadingDate else { return }
      dailyReview = loadedReview
      dailyReviewDraft = MobileDailyReviewDraft(review: loadedReview)
      dayReviewEvidence = loadedEvidence
      errorMessage = nil
    } catch {
      guard selectedReviewDate == loadingDate else { return }
      await presentUserFacingError(error)
    }
    if selectedReviewDate == loadingDate {
      isLoadingDailyReviewDraft = false
    }
  }

  public func selectReviewDay(_ date: String) async {
    guard await flushDailyReviewDraftIfNeeded() else { return }
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

  @discardableResult
  public func saveDailyReviewDraft() async -> Bool {
    guard selectedReviewDayIsEditable, dailyReviewDraft.canSave, !isSavingReview,
      !isLoadingDailyReviewDraft
    else {
      return false
    }
    isSavingReview = true
    defer { isSavingReview = false }

    do {
      let saved = try await core.upsertDailyReviewPreservingLinks(
        date: selectedReviewDate,
        summary: dailyReviewDraft.trimmedSummary,
        mood: dailyReviewDraft.mood,
        energyLevel: dailyReviewDraft.energy,
        wins: dailyReviewDraft.trimmedWins,
        blockers: dailyReviewDraft.trimmedBlockers,
        learnings: dailyReviewDraft.trimmedLearnings
      )
      dailyReview = saved
      dailyReviewDraft = MobileDailyReviewDraft(review: saved)
      dayReviewEvidence = try await core.loadDaySummary(date: selectedReviewDate)
      snapshot = MobileHomeSnapshot(
        today: snapshot.today,
        currentFocus: snapshot.currentFocus,
        weeklyReview: try await core.getWeeklyReviewSnapshot(weekOf: weeklyReviewAnchor)
      )
      await loadWeekReviewDigest(weekOf: weeklyReviewAnchor)
      errorMessage = nil
      feedbackProvider.playFeedback(.contentSaved)
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  public var dailyReviewDraftMatchesLoaded: Bool {
    dailyReviewDraft == MobileDailyReviewDraft(review: dailyReview)
  }

  public func flushDailyReviewDraftIfNeeded() async -> Bool {
    guard !dailyReviewDraftMatchesLoaded else { return true }
    return await saveDailyReviewDraft()
  }
}
