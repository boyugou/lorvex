import Foundation
import LorvexStore

extension SwiftLorvexCoreService {
  /// A real core over a fresh, empty in-memory GRDB store running the canonical
  /// schema (resolved exactly like the on-disk open: `LORVEX_APPLE_SCHEMA_PATH`
  /// override, then the bundled `schema.sql`, then the in-repo copy).
  ///
  /// Construction applies the full DDL immediately, so the returned service is
  /// ready for reads and writes with no on-disk footprint and no cross-test
  /// state. This is the backend for tests, previews, and headless design dumps;
  /// production surfaces open on-disk stores via `LorvexCoreRuntimeFactory`.
  public static func inMemory() throws -> SwiftLorvexCoreService {
    SwiftLorvexCoreService(store: try LorvexStore.openInMemory(schemaSQL: resolveSchemaSQL()))
  }
}
