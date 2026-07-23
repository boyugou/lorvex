import LorvexCore
@testable import LorvexWatch
import Testing

@Suite("Watch delivery policy")
struct WatchConnectivityForwarderTests {
  @Test("unavailable forwarding error is user-actionable")
  func unavailableForwardingErrorIsActionable() {
    let message = WatchForwardingError.unavailable.localizedDescription
    #expect(message.contains("not ready"))
    #expect(message.contains("iPhone"))
  }

  @Test("inactive and background delivery are distinct states")
  func inactiveAndBackgroundAreDistinct() {
    #expect(LorvexWatchDeliveryChannelState.inactive != .background)
    #expect(LorvexWatchDeliveryChannelState.reachable != .background)
  }

  @Test("retry delay grows exponentially and remains capped")
  func retryDelayIsCapped() {
    let policy = LorvexWatchDeliveryRetryPolicy(
      initialDelay: 2,
      maximumDelay: 30,
      acknowledgementTimeout: 11)

    #expect(policy.retryDelay(afterAttempt: 1) == 2)
    #expect(policy.retryDelay(afterAttempt: 2) == 4)
    #expect(policy.retryDelay(afterAttempt: 3) == 8)
    #expect(policy.retryDelay(afterAttempt: 20) == 30)
    #expect(policy.acknowledgementTimeout == 11)
  }
}
