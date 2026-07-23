import Foundation
import LorvexDomain

extension MobileStore {
  /// Schedule the next refresh at midnight in the synced product zone. A
  /// successful refresh always re-arms this task, including after a timezone
  /// preference arrives from CloudKit.
  func rescheduleLogicalDayBoundaryWake() {
    logicalDayBoundaryWakeTask?.cancel()
    logicalDayBoundaryWakeTask = nil

    let reference = now()
    guard let timezone = snapshot.today.timezone,
      let midnight = Timezone.nextMidnight(after: reference, timezoneName: timezone)
    else { return }

    let delay = max(0.25, midnight.timeIntervalSince(reference) + 0.25)
    logicalDayBoundaryWakeTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .seconds(delay))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      _ = await self?.refresh()
    }
  }
}
