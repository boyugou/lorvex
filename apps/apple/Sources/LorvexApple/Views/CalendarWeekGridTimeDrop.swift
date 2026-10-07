import LorvexCore
import SwiftUI
import UniformTypeIdentifiers

/// The drop target of one day column of the week grid's time axis. A task
/// dropped on it starts at the quarter hour under the pointer.
///
/// SwiftUI's `dropDestination` reports only whether a drag is over the view,
/// not where, so the column uses a delegate: it learns the pointer's position
/// on every update and can show the start before the drag is released. The
/// payload is read only on release, as the system allows.
struct TaskTimeDropDelegate: DropDelegate {
  /// Points per hour of the column, which turns the pointer's height into
  /// minutes.
  let hourHeight: CGFloat
  /// Called as the pointer moves over the column with the start a drop would
  /// give, and with nil when the drag leaves or ends.
  let hover: @MainActor (Int?) -> Void
  /// Called once on release with the start and the ids of the dropped tasks (a
  /// drag of a selected row carries the whole selection).
  let drop: @MainActor (Int, [LorvexTask.ID]) -> Void

  func validateDrop(info: DropInfo) -> Bool {
    info.hasItemsConforming(to: [.lorvexTask])
  }

  func dropEntered(info: DropInfo) {
    hover(startMinute(at: info.location))
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    hover(startMinute(at: info.location))
    return DropProposal(operation: .move)
  }

  func dropExited(info: DropInfo) {
    hover(nil)
  }

  func performDrop(info: DropInfo) -> Bool {
    let providers = info.itemProviders(for: [.lorvexTask])
    guard let provider = providers.first else { return false }
    let start = startMinute(at: info.location)
    hover(nil)
    let hover = hover
    let drop = drop
    _ = provider.loadTransferable(type: LorvexTaskRef.self) { result in
      Task { @MainActor in
        // SwiftUI reports the pointer over the column once more while the drop
        // completes, which would bring the indicator back; clearing it here,
        // after those callbacks, leaves the column bare.
        hover(nil)
        guard case .success(let reference) = result else { return }
        drop(start, [reference].droppedTaskIDs)
      }
    }
    return true
  }

  /// The quarter hour a drop at `location` would start at. The length of the
  /// dropped task is not known until release, so the start is not held back
  /// for it here; the store keeps the task's block inside the day.
  private func startMinute(at location: CGPoint) -> Int {
    CalendarGridMove.dropStart(atY: location.y, hourHeight: hourHeight, duration: 0)
  }
}
