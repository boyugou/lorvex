import Foundation
import LorvexCore

func withIsolatedAppIntentDatabase<T>(
  _ body: () async throws -> T
) async rethrows -> T {
  let path = NSTemporaryDirectory() + "lorvex-app-intent-\(UUID().uuidString).db"
  defer {
    for candidate in [path, "\(path)-shm", "\(path)-wal"] {
      try? FileManager.default.removeItem(atPath: candidate)
    }
  }
  return try await LorvexCoreRuntimeFactory.$databaseOverride.withValue(
    path,
    operation: body
  )
}
