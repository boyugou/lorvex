import Foundation
import LorvexCore
import LorvexMobile
import Testing

@MainActor
@Test
func mobileStoreExportsJSONDataThroughCore() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })

  let data = try #require(
    await store.exportData(format: .json, categories: Set(LorvexDataExportCategory.allCases)))
  let output = String(decoding: data, as: UTF8.self)

  #expect(output.contains("\"tasks\""))
  #expect(output.contains("\"lists\""))
  #expect(store.errorMessage == nil)
  #expect(store.isExportingData == false)
}

@MainActor
@Test
func mobileStoreExportsCSVDataThroughCore() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })

  let data = try #require(
    await store.exportData(format: .csv, categories: Set(LorvexDataExportCategory.allCases)))
  let output = String(decoding: data, as: UTF8.self)

  #expect(output.contains("## tasks"))
  #expect(output.contains("## lists"))
  #expect(store.errorMessage == nil)
  #expect(store.isExportingData == false)
}

@MainActor
@Test
func mobileStoreExportsZipPackageThroughCore() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })

  let data = try #require(
    await store.exportData(format: .zip, categories: Set(LorvexDataExportCategory.allCases)))

  // PK\03\04 local file header signature at the start of a ZIP archive.
  #expect(Array(data.prefix(4)) == [0x50, 0x4B, 0x03, 0x04])
  #expect(store.errorMessage == nil)
  #expect(store.isExportingData == false)
}
