import Foundation
import LorvexDomain

extension AppStore {
  /// Schedule the next refresh at midnight in the product's configured zone.
  /// Every successful Today load calls this again, so a synced/local timezone
  /// change cancels the old-zone deadline and installs the new one.
  func rescheduleLogicalDayBoundaryWake() {
    logicalDayBoundaryWakeTask?.cancel()
    logicalDayBoundaryWakeTask = nil

    let reference = now()
    guard let timezone = today.timezone,
      let midnight = Timezone.nextMidnight(after: reference, timezoneName: timezone)
    else { return }

    // Wake just beyond the exact boundary so filesystem/clock granularity cannot
    // make the core resolve the old day again. The refresh re-arms tomorrow.
    let delay = max(0.25, midnight.timeIntervalSince(reference) + 0.25)
    logicalDayBoundaryWakeTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .seconds(delay))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      await self?.refresh()
    }
  }
}
