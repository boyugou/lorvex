import Testing

@testable import LorvexCore

/// The sandbox detector prefers the process's signed `com.apple.security.app-sandbox`
/// entitlement and only falls back to `APP_SANDBOX_CONTAINER_ID` when the
/// entitlement can't be read. The env-var-only cases stand in for that fallback
/// (a `swift test` process is unsigned, so the real entitlement read returns
/// `nil`); the entitlement-seam cases prove the signed entitlement is the
/// authority and overrides the env var either way.
struct AppSandboxEnvironmentTests {
  @Test("mobile Apple platforms are always treated as sandboxed")
  func mobileApplePlatformsFailClosed() {
    #expect(AppSandboxEnvironment.isSandboxed(
      environment: [:],
      platformRequiresSandbox: true,
      signedEntitlement: { false }))
  }

  @Test("sandboxed when APP_SANDBOX_CONTAINER_ID is set (entitlement unreadable)")
  func sandboxedWhenContainerIDPresent() {
    #expect(AppSandboxEnvironment.isSandboxed(
      environment: ["APP_SANDBOX_CONTAINER_ID": "com.lorvex.apple"],
      signedEntitlement: { nil }))
  }

  @Test("not sandboxed when the environment carries no container id (entitlement unreadable)")
  func notSandboxedWhenContainerIDAbsent() {
    #expect(!AppSandboxEnvironment.isSandboxed(environment: [:], signedEntitlement: { nil }))
  }

  @Test("not sandboxed when the container id is present but empty")
  func notSandboxedWhenContainerIDEmpty() {
    #expect(!AppSandboxEnvironment.isSandboxed(
      environment: ["APP_SANDBOX_CONTAINER_ID": ""],
      signedEntitlement: { nil }))
  }

  @Test("ignores unrelated environment entries")
  func ignoresUnrelatedEntries() {
    #expect(!AppSandboxEnvironment.isSandboxed(
      environment: ["LORVEX_APPLE_DB_PATH": "/tmp/x.db"],
      signedEntitlement: { nil }))
  }

  @Test("a true signed entitlement is authoritative even with no container id")
  func signedEntitlementTrueWinsOverMissingEnv() {
    #expect(AppSandboxEnvironment.isSandboxed(environment: [:], signedEntitlement: { true }))
  }

  @Test("a false signed entitlement overrides a spoofed container id")
  func signedEntitlementFalseOverridesEnv() {
    // The env var claims sandboxed, but the real signed entitlement says
    // otherwise — the entitlement authority must win, so the storage policy
    // can't be forced by an injected variable.
    #expect(!AppSandboxEnvironment.isSandboxed(
      environment: ["APP_SANDBOX_CONTAINER_ID": "com.lorvex.apple"],
      signedEntitlement: { false }))
  }
}
