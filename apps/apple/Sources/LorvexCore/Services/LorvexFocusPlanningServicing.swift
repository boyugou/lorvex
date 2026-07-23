import Foundation

/// Privacy-filtered saved-schedule reads for AI-facing surfaces.
///
/// This is deliberately separate from ``LorvexFocusPlanningServicing``'s
/// human-facing ``LorvexFocusPlanningServicing/loadFocusSchedule(date:)``:
/// UI code must keep the complete stored block list so rendering followed by a
/// save cannot delete blocks that the current AI-access tier hides.
public protocol LorvexAIFocusScheduleReading: Sendable {
  /// Read a saved schedule through the device's calendar AI-access tier.
  /// Provider blocks are omitted at `off`, reduced to anonymous occupancy at
  /// `busyOnly`, and returned with local detail at `fullDetails`.
  func loadFocusScheduleForAI(date: String) async throws -> FocusSchedule?
}

public protocol LorvexFocusPlanningServicing: Sendable {
  func loadCurrentFocus(date: String) async throws -> CurrentFocusPlan?

  func setCurrentFocus(
    date: String,
    taskIDs: [LorvexTask.ID],
    briefing: String?,
    timezone: String
  ) async throws -> CurrentFocusPlan

  func addToCurrentFocus(
    date: String,
    taskIDs: [LorvexTask.ID],
    briefing: String?,
    timezone: String
  ) async throws -> CurrentFocusPlan

  func clearCurrentFocus(date: String) async throws -> CurrentFocusPlan?

  func removeFromCurrentFocus(date: String, taskID: LorvexTask.ID) async throws -> CurrentFocusPlan?

  func loadFocusSchedule(date: String) async throws -> FocusSchedule?

  func proposeFocusSchedule(date: String) async throws -> FocusSchedule

  /// Proposal with per-call options. `workingHoursStart`/`workingHoursEnd`
  /// (HH:MM) override the stored preference for this proposal only;
  /// `includeCalendarEvents: false` schedules as if the calendar were empty.
  /// `nil` options keep the stored/default behavior.
  func proposeFocusSchedule(
    date: String,
    workingHoursStart: String?,
    workingHoursEnd: String?,
    includeCalendarEvents: Bool?
  ) async throws -> FocusSchedule

  func saveFocusSchedule(date: String, blocks: [FocusScheduleBlock], rationale: String?)
    async throws
    -> FocusSchedule

  /// Delete the saved time-block schedule for `date` (header + blocks). Used when
  /// clearing the day's focus plan so the schedule does not survive in storage
  /// and reappear on the next load. A no-op when no schedule exists for the date.
  func clearFocusSchedule(date: String) async throws
}
