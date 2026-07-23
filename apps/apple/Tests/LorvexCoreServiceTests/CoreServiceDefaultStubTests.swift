import Foundation
import Testing

@Test
func coreServiceProtocolsDoNotShipUnsupportedDefaultStubs() throws {
  let serviceDirectory = packageRoot()
    .appending(path: "Sources/LorvexCore/Services")
  let files = try FileManager.default.contentsOfDirectory(
    at: serviceDirectory,
    includingPropertiesForKeys: nil
  )
  let defaultStubFiles = files
    .filter { $0.lastPathComponent.hasSuffix("Servicing+Defaults.swift") }
    .map(\.lastPathComponent)
    .filter { $0 != "LorvexTaskServicing+Defaults.swift" }

  #expect(
    defaultStubFiles.isEmpty,
    "Core service requirements must be implemented by conformers, not hidden behind runtime default stubs: \(defaultStubFiles)"
  )
}

private func packageRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}
