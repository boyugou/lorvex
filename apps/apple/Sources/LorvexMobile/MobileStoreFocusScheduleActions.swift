import Foundation
import LorvexCore

extension MobileStore {
  public func proposeFocusSchedule() async {
    guard !isProposingFocusSchedule else { return }
    isProposingFocusSchedule = true
    defer { isProposingFocusSchedule = false }
    do {
      proposedFocusSchedule = try await core.proposeFocusSchedule(date: logicalTodayString)
      errorMessage = nil
    } catch {
      await presentUserFacingError(error)
    }
  }

  public func saveProposedFocusSchedule() async {
    guard let proposedFocusSchedule, !isSavingFocusSchedule else { return }
    isSavingFocusSchedule = true
    defer { isSavingFocusSchedule = false }
    do {
      let saved = try await core.saveFocusSchedule(
        date: proposedFocusSchedule.date,
        blocks: proposedFocusSchedule.blocks,
        rationale: proposedFocusSchedule.rationale
          ?? String(localized: "focus.schedule.rationale.savedFromLorvex", defaultValue: "Saved from Lorvex", table: "Localizable", bundle: MobileL10n.bundle)
      )
      let date = saved.date
      focusSchedule = saved
      self.proposedFocusSchedule = nil
      snapshot.currentFocus = try await core.loadCurrentFocus(date: date)
      snapshot.today = try await core.loadToday()
      await publishMobileSyncSurfaces()
      await rescheduleReminders()
      await updateBadge()
      errorMessage = nil
    } catch {
      await presentUserFacingError(error)
    }
  }

  public func discardProposedFocusSchedule() {
    proposedFocusSchedule = nil
  }

  public func clearCurrentFocus() async {
    guard !isClearingFocusSchedule else { return }
    isClearingFocusSchedule = true
    defer { isClearingFocusSchedule = false }
    do {
      let date = logicalTodayString
      snapshot.currentFocus = try await core.clearCurrentFocus(date: date)
      try await core.clearFocusSchedule(date: date)
      focusSchedule = nil
      proposedFocusSchedule = nil
      snapshot.today = try await core.loadToday()
      await publishMobileSyncSurfaces()
      await rescheduleReminders()
      await updateBadge()
      errorMessage = nil
    } catch {
      await presentUserFacingError(error)
    }
  }
}
