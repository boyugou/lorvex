import LorvexCore

extension LorvexTaskIntentRunner {
  public static func saveMemory(
    key: String,
    content: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> MemoryEntry {
    try await LorvexSystemIntentRunner.saveMemory(key: key, content: content, core: core)
  }

  public static func readMemory(
    key: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> MemoryEntry {
    try await LorvexSystemIntentRunner.readMemory(key: key, core: core)
  }

  public static func deleteMemory(
    key: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> String {
    try await LorvexSystemIntentRunner.deleteMemory(key: key, core: core)
  }
}
