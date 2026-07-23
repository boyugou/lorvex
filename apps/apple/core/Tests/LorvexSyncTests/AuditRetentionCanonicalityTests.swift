import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class AuditRetentionCanonicalityTests: XCTestCase {
  private let account = "canonical-policy-version-account"
  private let zone = "canonical-policy-version-zone"
  private let canonicalVersion = "6000000000000_0001_a1b2c3d4a1b2c3d4"
  private let unpaddedVersion = "6000000000000_1_a1b2c3d4a1b2c3d4"
  private let uppercaseVersion = "6000000000000_0001_A1B2C3D4A1B2C3D4"

  func testIncomingParseableButNoncanonicalPolicyVersionsAreRejected() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: account, zoneName: zone)

      for noncanonical in [unpaddedVersion, uppercaseVersion] {
        XCTAssertNoThrow(try Hlc.parse(noncanonical), "fixture must remain parseable")
        XCTAssertThrowsError(
          try AuditRetentionFrontier.adoptPolicyForActiveAccount(
            db, accountIdentifier: account, policy: .maximum,
            policyVersion: noncanonical)
        ) { error in
          XCTAssertEqual(
            error as? AuditRetentionStateError,
            .malformedAccountState(self.account))
        }
      }

      XCTAssertNoThrow(
        try AuditRetentionFrontier.adoptPolicyForActiveAccount(
          db, accountIdentifier: account, policy: .maximum,
          policyVersion: canonicalVersion))
    }
  }

  func testPersistedParseableButNoncanonicalPolicyVersionFailsClosed() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: account, zoneName: zone)
      // Simulate a damaged/restored SQLite file that bypassed normal CHECK
      // enforcement. The typed reader must still fail closed.
      try db.execute(sql: "PRAGMA ignore_check_constraints = ON")
      try db.execute(
        sql: "UPDATE audit_retention_account_state SET policy_version = ? WHERE account_identifier = ?",
        arguments: [uppercaseVersion, account])
      try db.execute(sql: "PRAGMA ignore_check_constraints = OFF")

      XCTAssertThrowsError(
        try AuditRetentionFrontier.state(db, accountIdentifier: account)
      ) { error in
        XCTAssertEqual(
          error as? AuditRetentionStateError,
          .malformedAccountState(self.account))
      }
    }
  }
}
