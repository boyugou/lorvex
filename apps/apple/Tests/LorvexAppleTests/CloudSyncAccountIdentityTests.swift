import Foundation
import LorvexCloudSync
import Testing

private enum AccountIdentityTestError: Error {
  case unavailable
}

@Suite("Cloud sync account identity")
struct CloudSyncAccountIdentityTests {
  @Test
  func cloudKitUserRecordNameProducesStableOpaqueIdentifier() async {
    let first = CloudKitUserRecordAccountIdentifier(recordNameProvider: { "_user_a" })
    let second = CloudKitUserRecordAccountIdentifier(recordNameProvider: { "_user_a" })
    let other = CloudKitUserRecordAccountIdentifier(recordNameProvider: { "_user_b" })

    let firstID = await first.currentAccountIdentifier()
    let secondID = await second.currentAccountIdentifier()
    let otherID = await other.currentAccountIdentifier()

    #expect(firstID != nil)
    // The identity is an opaque hash, never the raw record name.
    #expect(firstID != "_user_a")
    // Stable per account, distinct across accounts.
    #expect(firstID == secondID)
    #expect(firstID != otherID)
  }

  @Test
  func userRecordLookupFailureReturnsNilFailClosed() async {
    // FAIL-CLOSED: with a single identity format and no offline fallback, a
    // failed current-user record lookup returns `nil` ("unknown") so the caller
    // skips the cycle rather than syncing under or persisting an alternate
    // identity.
    let identifier = CloudKitUserRecordAccountIdentifier(
      recordNameProvider: { throw AccountIdentityTestError.unavailable })

    #expect(await identifier.currentAccountIdentifier() == nil)
  }

  @Test
  func emptyUserRecordNameReturnsNil() async {
    // A blank record name is not a usable identity — treated as unknown.
    let identifier = CloudKitUserRecordAccountIdentifier(recordNameProvider: { "" })

    #expect(await identifier.currentAccountIdentifier() == nil)
  }
}
