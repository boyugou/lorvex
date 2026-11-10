import Foundation

/// Runs a piece of work once for a burst of signals, and once more when a
/// signal arrived while it was running, so nothing signalled is missed and
/// nothing runs once per signal.
///
/// A system change notice often arrives in bursts (a calendar sync posts one
/// per changed event), and a loop that awaits its work per notice replays the
/// whole burst as that many sequential runs. ``signal(_:)`` returns at once, so
/// the loop reading the notices drains the burst while the first run is still
/// going, and the run that follows sees everything the burst changed.
public actor BurstCoalescer {
  private var isRunning = false
  private var hasPending = false

  public init() {}

  /// Asks for a run of `work`. Starts one when none is running; otherwise
  /// marks one more to follow the run in flight, however many signals arrive
  /// meanwhile.
  public func signal(_ work: @escaping @Sendable () async -> Void) {
    guard !isRunning else {
      hasPending = true
      return
    }
    isRunning = true
    Task { await self.run(work) }
  }

  private func run(_ work: @Sendable () async -> Void) async {
    repeat {
      hasPending = false
      await work()
    } while hasPending
    isRunning = false
  }
}
