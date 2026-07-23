import LorvexStore
import XCTest

@testable import LorvexCore

final class SwiftLorvexCoreServiceReadOnlyTests: XCTestCase {
  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return SwiftLorvexCoreService(store: store)
  }

  private func deviceID(_ service: SwiftLorvexCoreService) throws -> String? {
    try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT value FROM sync_checkpoints WHERE key = 'device_id'")
    }
  }

  func testSessionContextDoesNotCreateDeviceIdentity() async throws {
    let service = try makeService()
    XCTAssertNil(try deviceID(service))

    let context = try await service.getSessionContext()

    XCTAssertNil(context.deviceID)
    XCTAssertNil(try deviceID(service))
  }

  func testRuntimeDiagnosticsDoesNotCreateDeviceIdentity() async throws {
    let service = try makeService()
    XCTAssertNil(try deviceID(service))

    let diagnostics = try await service.loadRuntimeDiagnostics()

    XCTAssertNil(diagnostics.sync.deviceID)
    XCTAssertNil(try deviceID(service))
  }

  func testFirstWriteCreatesDeviceIdentity() async throws {
    let service = try makeService()
    XCTAssertNil(try deviceID(service))

    _ = try await service.createTask(title: "Device identity write", notes: "")

    XCTAssertNotNil(try deviceID(service))
  }
}
