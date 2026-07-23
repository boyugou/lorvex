import Foundation
import LorvexCore
import LorvexMobile
import Testing

@MainActor
@Test
func mobileStoreLoadsRuntimeDiagnosticsThroughCore() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore())

  await store.loadRuntimeDiagnostics()
  let diagnostics = try #require(store.runtimeDiagnostics)

  #expect(diagnostics.setup.setupCompleted)
  #expect(diagnostics.sync.backend == "unknown")
  #expect(store.errorMessage == nil)
  #expect(store.isLoadingRuntimeDiagnostics == false)
}
