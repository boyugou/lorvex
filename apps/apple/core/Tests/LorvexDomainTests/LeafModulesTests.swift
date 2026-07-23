import XCTest

@testable import LorvexDomain

// MARK: - ProviderKind

final class ProviderKindTests: XCTestCase {
  func testAllowlistAcceptsEveryCanonicalKind() {
    for kind in ProviderKind.allowlist {
      XCTAssertTrue(ProviderKind.isAllowedProviderKind(kind), "\(kind) must be allowed")
    }
  }

  func testAllowlistRejectsUnknown() {
    for bad in [
      "", " eventkit", "EventKit", "EVENTKIT", "evernote", "google", "eventkit_v2",
      "ICAL_SUBSCRIPTION",
      // Reduced out of the 1.0 allowlist: only EventKit ships a writer, so
      // linking a task to any of these could never resolve.
      "google_calendar", "ics", "linux_ics", "outlook", "windows_appointments",
    ] {
      XCTAssertFalse(ProviderKind.isAllowedProviderKind(bad), "\(bad) must be rejected")
    }
  }

  func testAllowlistCoversEveryRealProducer() {
    // EventKit is the only provider kind with a shipping writer/refresh path, so
    // it is the sole allowed kind.
    XCTAssertEqual(ProviderKind.allowlist, ["eventkit"])
    XCTAssertTrue(ProviderKind.isAllowedProviderKind("eventkit"))
  }

  func testAllowlistDisplay() {
    XCTAssertEqual(ProviderKind.allowlistDisplay(), "eventkit")
  }
}

// MARK: - ProviderLink

final class ProviderLinkTests: XCTestCase {
  func testNormalizesAndValidates() {
    let result = ProviderLink.normalizeFields(
      providerKind: "eventkit",
      providerScope: "  default\u{200B}  ",
      providerEventKey: "\u{202E}event-1\u{202C}")
    switch result {
    case .success(let f):
      XCTAssertEqual(f.providerKind, "eventkit")
      XCTAssertEqual(f.providerScope, "default")
      XCTAssertEqual(f.providerEventKey, "event-1")
    case .failure(let e):
      XCTFail("expected success, got \(e)")
    }
  }

  func testAcceptsEmptyScopeForSingleScopeProviders() {
    let result = ProviderLink.normalizeFields(
      providerKind: "eventkit", providerScope: "", providerEventKey: "event-1")
    switch result {
    case .success(let f): XCTAssertEqual(f.providerScope, "")
    case .failure(let e): XCTFail("expected success, got \(e)")
    }
  }

  func testRejectsOverlongScopeAndUnknownKind() {
    let tooLong = String(repeating: "a", count: ProviderLink.maxFieldLength + 1)
    if case .failure(let e) = ProviderLink.normalizeFields(
      providerKind: "eventkit", providerScope: tooLong, providerEventKey: "event-1"),
      case .tooLong(let field, _, _) = e
    {
      XCTAssertEqual(field, "provider_scope")
    } else {
      XCTFail("expected tooLong(provider_scope)")
    }
    if case .failure(let e) = ProviderLink.normalizeFields(
      providerKind: "evernote", providerScope: "default", providerEventKey: "event-1")
    {
      XCTAssertTrue(e.description.contains("not in the allowlist"))
    } else {
      XCTFail("expected failure for unknown provider kind")
    }
  }
}

// MARK: - Merge

final class MergeTests: XCTestCase {
  func testLwwRemoteWinsWhenStrictlyNewer() {
    let local = try! Hlc(physicalMs: 1000, counter: 0, deviceSuffix: "10ca100100000001")
    let remote = try! Hlc(physicalMs: 2000, counter: 0, deviceSuffix: "de0070e100000001")
    XCTAssertEqual(Merge.resolveLww(local: local, remote: remote), .remoteWins)
  }

  func testLwwLocalWinsWhenStrictlyNewer() {
    let local = try! Hlc(physicalMs: 3000, counter: 0, deviceSuffix: "10ca100100000001")
    let remote = try! Hlc(physicalMs: 1000, counter: 0, deviceSuffix: "de0070e100000001")
    XCTAssertEqual(Merge.resolveLww(local: local, remote: remote), .localWins)
  }

  func testLwwLocalWinsOnEqualVersions() {
    let local = try! Hlc(physicalMs: 1000, counter: 5, deviceSuffix: "aabbccddaabbccdd")
    let remote = try! Hlc(physicalMs: 1000, counter: 5, deviceSuffix: "aabbccddaabbccdd")
    XCTAssertEqual(Merge.resolveLww(local: local, remote: remote), .localWins)
  }

  func testLwwRemoteWinsByCounter() {
    let local = try! Hlc(physicalMs: 1000, counter: 0, deviceSuffix: "dec0000100000001")
    let remote = try! Hlc(physicalMs: 1000, counter: 1, deviceSuffix: "dec0000200000001")
    XCTAssertEqual(Merge.resolveLww(local: local, remote: remote), .remoteWins)
  }

  func testLwwLocalWinsByCounter() {
    let local = try! Hlc(physicalMs: 1000, counter: 5, deviceSuffix: "dec0000100000001")
    let remote = try! Hlc(physicalMs: 1000, counter: 3, deviceSuffix: "dec0000200000001")
    XCTAssertEqual(Merge.resolveLww(local: local, remote: remote), .localWins)
  }

  func testLwwRemoteWinsBySuffixTiebreak() {
    let local = try! Hlc(physicalMs: 1000, counter: 0, deviceSuffix: "aaaa0000aaaa0000")
    let remote = try! Hlc(physicalMs: 1000, counter: 0, deviceSuffix: "bbbb0000bbbb0000")
    XCTAssertEqual(Merge.resolveLww(local: local, remote: remote), .remoteWins)
  }

  func testLwwLocalWinsBySuffixTiebreak() {
    let local = try! Hlc(physicalMs: 1000, counter: 0, deviceSuffix: "ffff0000ffff0000")
    let remote = try! Hlc(physicalMs: 1000, counter: 0, deviceSuffix: "aaaa0000aaaa0000")
    XCTAssertEqual(Merge.resolveLww(local: local, remote: remote), .localWins)
  }

  func testLwwIsIdempotent() {
    let local = try! Hlc(physicalMs: 500, counter: 3, deviceSuffix: "deafbeefdeafbeef")
    let remote = try! Hlc(physicalMs: 500, counter: 3, deviceSuffix: "deafbeefdeafbeef")
    XCTAssertEqual(Merge.resolveLww(local: local, remote: remote), .localWins)
  }

  func testTagMergeFirstSmaller() {
    let (w, l) = Merge.tagMergeWinner("01966a3f-0001", "01966a3f-0002")
    XCTAssertEqual(w, "01966a3f-0001")
    XCTAssertEqual(l, "01966a3f-0002")
  }

  func testTagMergeSecondSmaller() {
    let (w, l) = Merge.tagMergeWinner("01966a3f-0009", "01966a3f-0003")
    XCTAssertEqual(w, "01966a3f-0003")
    XCTAssertEqual(l, "01966a3f-0009")
  }

  func testTagMergeEqualIds() {
    let (w, l) = Merge.tagMergeWinner("same-id", "same-id")
    XCTAssertEqual(w, "same-id")
    XCTAssertEqual(l, "same-id")
  }

  func testTagMergeIsDeterministic() {
    let (w1, l1) = Merge.tagMergeWinner("alpha", "beta")
    let (w2, l2) = Merge.tagMergeWinner("beta", "alpha")
    XCTAssertEqual(w1, w2)
    XCTAssertEqual(l1, l2)
  }

  func testTagMergeUuidv7Chrono() {
    let earlier = "01966a3f-7c8b-7d4e-8000-000000000001"
    let later = "01966a40-0000-7d4e-8000-000000000001"
    let (w, _) = Merge.tagMergeWinner(earlier, later)
    XCTAssertEqual(w, earlier)
  }

}

// MARK: - StorageSchema

final class StorageSchemaTests: XCTestCase {
  func testIdentifiesAllBoolColumns() {
    for (t, c) in StorageSchema.sqliteBoolColumns {
      XCTAssertTrue(StorageSchema.isSqliteBoolColumn(table: t, column: c))
    }
  }

  func testRejectsNonBoolColumns() {
    XCTAssertFalse(StorageSchema.isSqliteBoolColumn(table: "tasks", column: "priority"))
    XCTAssertFalse(
      StorageSchema.isSqliteBoolColumn(table: "habit_reminder_policies", column: "reminder_time"))
    XCTAssertFalse(StorageSchema.isSqliteBoolColumn(table: "calendar_events", column: "title"))
  }

  func testRejectsSyncedColumnsAsDeviceLocal() {
    XCTAssertFalse(StorageSchema.isDeviceLocalColumn(table: "memories", column: "content"))
    XCTAssertFalse(StorageSchema.isDeviceLocalColumn(table: "tasks", column: "title"))
  }
}

// MARK: - Sql

final class SqlTests: XCTestCase {
  func testInZeroCount() { XCTAssertEqual(Sql.sqlInPlaceholders(0, 0), "") }
  func testInThreeFromZero() { XCTAssertEqual(Sql.sqlInPlaceholders(3, 0), "?1, ?2, ?3") }
  func testInTwoWithOffset5() { XCTAssertEqual(Sql.sqlInPlaceholders(2, 5), "?6, ?7") }
  func testInSinglePlaceholder() { XCTAssertEqual(Sql.sqlInPlaceholders(1, 0), "?1") }
  func testInSingleWithOffset() { XCTAssertEqual(Sql.sqlInPlaceholders(1, 3), "?4") }

  func testCsvZero() { XCTAssertEqual(Sql.sqlCsvPlaceholders(0), "") }
  func testCsvOne() { XCTAssertEqual(Sql.sqlCsvPlaceholders(1), "?") }
  func testCsvTwo() { XCTAssertEqual(Sql.sqlCsvPlaceholders(2), "?, ?") }
  func testCsvThree() { XCTAssertEqual(Sql.sqlCsvPlaceholders(3), "?, ?, ?") }
  func testCsv64() {
    let count = 64
    let out = Sql.sqlCsvPlaceholders(count)
    XCTAssertEqual(out.count, 3 * count - 2)
    XCTAssertTrue(out.hasPrefix("?, ?"))
    XCTAssertTrue(out.hasSuffix(", ?"))
  }
}

// MARK: - SerdeSupport

final class SerdeSupportTests: XCTestCase {
  func testFiniteIsNumber() {
    let v = SerdeSupport.sqliteRealToJson(2.5)
    if case .double(let d) = v { XCTAssertEqual(d, 2.5) } else { XCTFail("not double") }
  }

  func testNanSentinel() {
    XCTAssertEqual(SerdeSupport.sqliteRealToJson(.nan), .string("NaN"))
  }

  func testPositiveInfinity() {
    XCTAssertEqual(SerdeSupport.sqliteRealToJson(.infinity), .string("Infinity"))
  }

  func testNegativeInfinity() {
    XCTAssertEqual(SerdeSupport.sqliteRealToJson(-.infinity), .string("-Infinity"))
  }
}
