/// Holds a daily-review read or write until released, so a test can act while
/// a save or a load is in flight. Install it through
/// `StubCoreService.upsertDailyReviewGate` or `loadDailyReviewGate`:
/// `waitUntilHeld()` returns once the operation reached the gate, and
/// `release()` lets it finish.
actor ReviewGate {
  private var held = false
  private var released = false
  private var heldContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func hold() async {
    held = true
    heldContinuation?.resume()
    heldContinuation = nil
    if !released {
      await withCheckedContinuation { releaseContinuation = $0 }
    }
  }

  func waitUntilHeld() async {
    if held { return }
    await withCheckedContinuation { heldContinuation = $0 }
  }

  func release() {
    released = true
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}
