import Foundation
import LorvexCore

/// Holds runtime state for the focus domain: the active today snapshot, current
/// focus plan, and scheduled/proposed focus schedules.
struct AppStoreFocusStorage {
  var today: TodaySnapshot = .empty
  var currentFocus: CurrentFocusPlan? {
    didSet { focusedTaskIDSet = Set(currentFocus?.taskIDs ?? []) }
  }
  /// O(1) membership cache for `currentFocus?.taskIDs`, rebuilt only when
  /// `currentFocus` is assigned. SwiftUI rows test focus membership once or
  /// twice per `body`; over N rows, reading this cached set avoids hashing the
  /// whole task-ID list into a new `Set` on every access.
  private(set) var focusedTaskIDSet: Set<String> = []
  var focusSchedule: FocusSchedule?
  var proposedFocusSchedule: FocusSchedule?
  var focusSurfaceTaskCache: [LorvexTask.ID: LorvexTask] = [:]
  var selectedTaskIDs = Set<LorvexTask.ID>()

  mutating func reset() {
    today = .empty
    currentFocus = nil
    focusSchedule = nil
    proposedFocusSchedule = nil
    focusSurfaceTaskCache = [:]
    selectedTaskIDs.removeAll()
  }
}
