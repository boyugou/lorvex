actor IdempotencyInFlightClaims {
  private struct Claim: Hashable {
    let tool: String
    let key: String
  }

  private var claims: Set<Claim> = []
  private var waiters: [Claim: [CheckedContinuation<Void, Never>]] = [:]

  func tryClaim(tool: String, key: String) -> Bool {
    claims.insert(Claim(tool: tool, key: key)).inserted
  }

  func waitForRelease(tool: String, key: String) async {
    let claim = Claim(tool: tool, key: key)
    guard claims.contains(claim) else { return }
    await withCheckedContinuation { continuation in
      waiters[claim, default: []].append(continuation)
    }
  }

  func release(tool: String, key: String) {
    let claim = Claim(tool: tool, key: key)
    claims.remove(claim)
    let continuations = waiters.removeValue(forKey: claim) ?? []
    continuations.forEach { $0.resume() }
  }
}
