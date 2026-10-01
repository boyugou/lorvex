import Foundation
import LorvexStore

extension SwiftLorvexCoreService {
  /// A real core over a fresh, empty in-memory GRDB store running the canonical
  /// schema and migration ladder, both resolved exactly like the on-disk open
  /// (environment override, then the bundled copy, then the in-repo copy).
  ///
  /// Construction applies the full DDL immediately, so the returned service is
  /// ready for reads and writes with no on-disk footprint and no cross-test
  /// state. This is the backend for tests, previews, and headless design dumps;
  /// production surfaces open on-disk stores via `LorvexCoreRuntimeFactory`.
  /// `wallClock` is the instant time-of-day reads treat as now.
  public static func inMemory(
    wallClock: @escaping @Sendable () -> Date = { Date() }
  ) throws -> SwiftLorvexCoreService {
    SwiftLorvexCoreService(
      store: try LorvexStore.openInMemory(
        schemaSQL: resolveSchemaSQL(), migrations: resolveSchemaMigrations()),
      wallClock: wallClock)
  }
}
