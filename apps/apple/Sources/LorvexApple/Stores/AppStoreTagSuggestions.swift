import Foundation
import LorvexCore

extension AppStore {
  /// Every tag on a task that is not archived, sorted by name: the tags the
  /// task detail's tags picker offers. A failed read is logged and offers no
  /// tags; the picker still takes a typed tag.
  func loadKnownTags() async -> [String] {
    do {
      return try await core.listAllTags()
    } catch {
      try? await core.appendDiagnosticLog(
        source: "tags.suggestions",
        level: "error",
        message: "Loading tag suggestions failed.",
        details: UserFacingError.classify(error).technicalDetail)
      return []
    }
  }
}
