import Foundation
import LorvexCore

extension AppStore {
  func loadFocusSchedule() async {
    await perform {
      focusSchedule = try await core.loadFocusSchedule(date: logicalTodayDateString)
    }
  }

  func proposeFocusSchedule() async {
    await perform {
      proposedFocusSchedule = try await core.proposeFocusSchedule(date: logicalTodayDateString)
    }
  }

  func saveProposedFocusSchedule() async {
    guard let proposedFocusSchedule else { return }
    await perform {
      let saved = try await core.saveFocusSchedule(
        date: proposedFocusSchedule.date,
        blocks: proposedFocusSchedule.blocks,
        rationale: proposedFocusSchedule.rationale ?? "Saved from Lorvex"
      )
      focusSchedule = saved
      self.proposedFocusSchedule = nil
      currentFocus = try await core.loadCurrentFocus(date: saved.date)
      today = try await core.loadToday()
      await republishSurfacesAfterLocalMutation()
    }
  }
}
