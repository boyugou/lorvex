import Foundation

extension LorvexSystemIntentRunner {
  public static func readMemory(
    key: String,
    core: any LorvexCoreServicing
  ) async throws -> MemoryEntry {
    let trimmedKey = try validatedMemoryKey(key)
    let memory = try await core.loadMemory()
    guard let entry = memory.entries.first(where: { $0.key == trimmedKey }) else {
      throw LorvexCoreError.notFound(entity: .memory, id: trimmedKey)
    }
    return entry
  }

  public static func saveMemory(
    key: String,
    content: String,
    core: any LorvexCoreServicing
  ) async throws -> MemoryEntry {
    let trimmedKey = try validatedMemoryKey(key)
    let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedContent.isEmpty else {
      throw LorvexCoreError.validation(field: "content", message: "Memory content is required.")
    }
    return try await core.upsertMemory(key: trimmedKey, content: trimmedContent)
  }

  public static func deleteMemory(
    key: String,
    core: any LorvexCoreServicing
  ) async throws -> String {
    let trimmedKey = try validatedMemoryKey(key)
    _ = try await core.deleteMemory(key: trimmedKey)
    return trimmedKey
  }

  private static func validatedMemoryKey(_ key: String) throws -> String {
    let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedKey.isEmpty else {
      throw LorvexCoreError.validation(field: "key", message: "A memory key is required.")
    }
    return trimmedKey
  }
}
