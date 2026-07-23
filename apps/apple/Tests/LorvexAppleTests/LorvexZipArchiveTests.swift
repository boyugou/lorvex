import Foundation
import LorvexCore
import Testing

// MARK: - Known-answer CRC-32

@Test
func crc32MatchesKnownVectorForASCIIString() {
  // CRC-32 of "123456789" is the standard test vector 0xCBF43926.
  #expect(LorvexZipArchive.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
}

@Test
func crc32OfEmptyDataIsZero() {
  #expect(LorvexZipArchive.crc32(Data()) == 0)
}

// MARK: - Structural round-trip

@Test
func archiveStartsWithLocalFileHeaderSignature() throws {
  let zip = try LorvexZipArchive.archive(entries: [
    .init(path: "a.txt", data: Data("hello".utf8))
  ])
  #expect(Array(zip.prefix(4)) == [0x50, 0x4B, 0x03, 0x04])
}

@Test
func emptyArchiveIsJustAnEndOfCentralDirectoryRecord() throws {
  let zip = try LorvexZipArchive.archive(entries: [])
  // 22-byte EOCD with no entries and zero comment length.
  #expect(zip.count == 22)
  #expect(Array(zip.prefix(4)) == [0x50, 0x4B, 0x05, 0x06])
}

@Test
func writerRejectsDuplicateEntryPaths() {
  #expect(throws: LorvexZipArchive.WriteError.duplicateEntryPath("tasks.json")) {
    _ = try LorvexZipArchive.archive(entries: [
      .init(path: "tasks.json", data: Data("[]".utf8)),
      .init(path: "tasks.json", data: Data("[]".utf8)),
    ])
  }
}

@Test
func writerRejectsEntryCountBeforeClassicZipHeaderWraparound() {
  let entries = (0...LorvexZipArchive.maxEntryCount).map {
    LorvexZipArchive.Entry(path: "\($0).json", data: Data())
  }
  #expect(
    throws: LorvexZipArchive.WriteError.tooManyEntries(
      count: LorvexZipArchive.maxEntryCount + 1,
      limit: LorvexZipArchive.maxEntryCount)
  ) {
    _ = try LorvexZipArchive.archive(entries: entries)
  }
}

@Test
func writerRejectsPathLengthBeforeClassicZipHeaderWraparound() {
  let path = String(repeating: "a", count: Int(UInt16.max) + 1)
  #expect(
    throws: LorvexZipArchive.WriteError.pathTooLong(
      path: path, byteCount: path.utf8.count, limit: Int(UInt16.max))
  ) {
    _ = try LorvexZipArchive.archive(entries: [.init(path: path, data: Data())])
  }
}

// MARK: - Round-trip via /usr/bin/unzip (independent oracle)

@Test
func archiveUnzipsBackToOriginalContents() throws {
  let entries: [LorvexZipArchive.Entry] = [
    .init(path: "tasks.json", data: Data("[{\"id\":\"t1\"}]".utf8)),
    .init(path: "manifest.json", data: Data("{\"schemaVersion\":\"1\"}".utf8)),
    .init(path: "notes.txt", data: Data("line one\nline two\n".utf8)),
  ]
  let zip = try LorvexZipArchive.archive(entries: entries)

  let dir = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("lorvex-zip-test-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }
  let zipURL = dir.appendingPathComponent("archive.zip")
  try zip.write(to: zipURL)

  // -t verifies CRC integrity of every entry against an independent decoder.
  #expect(try runUnzip(arguments: ["-t", zipURL.path]).status == 0)

  // -p streams a named entry's raw bytes; compare against the originals.
  for entry in entries {
    let result = try runUnzip(arguments: ["-p", zipURL.path, entry.path])
    #expect(result.status == 0)
    #expect(result.stdout == entry.data)
  }
}

private struct UnzipResult {
  let status: Int32
  let stdout: Data
}

private func runUnzip(arguments: [String]) throws -> UnzipResult {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
  process.arguments = arguments
  let stdout = Pipe()
  process.standardOutput = stdout
  process.standardError = Pipe()
  try process.run()
  let data = stdout.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  return UnzipResult(status: process.terminationStatus, stdout: data)
}

// MARK: - Zip reader round-trip (against the writer)

@Test
func readerRoundTripsWriterOutputExactly() throws {
  let entries: [LorvexZipArchive.Entry] = [
    .init(path: "manifest.json", data: Data("{\"schemaVersion\":\"1\"}".utf8)),
    .init(path: "tasks.json", data: Data("[{\"id\":\"t1\"}]".utf8)),
    .init(path: "blobs/abc123", data: Data((0...255).map { UInt8($0) })),
    .init(path: "notes.txt", data: Data()),  // empty entry
  ]
  let archive = try LorvexZipArchive.archive(entries: entries)
  let read = try LorvexZipArchive.read(archive)

  #expect(read.count == entries.count)
  for (original, decoded) in Swift.zip(entries, read) {
    #expect(decoded.path == original.path)
    #expect(decoded.data == original.data)
  }
}

@Test
func readerHandlesEmptyArchive() throws {
  let read = try LorvexZipArchive.read(try LorvexZipArchive.archive(entries: []))
  #expect(read.isEmpty)
}

@Test
func readerRejectsNonZipBytes() {
  #expect(throws: LorvexZipArchive.ReadError.missingEndOfCentralDirectory) {
    _ = try LorvexZipArchive.read(Data("not a zip file".utf8))
  }
}

@Test
func readerRejectsCorruptedEntryViaCRC() throws {
  // Build a valid archive, then flip a byte inside the first entry's stored
  // payload so its CRC no longer matches. The stored payload starts right after
  // the 30-byte local header + the filename (no extra field, no compression).
  let entry = LorvexZipArchive.Entry(path: "a.txt", data: Data("hello world".utf8))
  var zip = try LorvexZipArchive.archive(entries: [entry])
  let payloadStart = 30 + "a.txt".utf8.count
  zip[payloadStart] ^= 0xFF

  #expect(throws: (any Error).self) {
    _ = try LorvexZipArchive.read(zip)
  }
}

@Test
func readerRejectsStoredEntryWhoseDeclaredSizesDisagree() throws {
  var zip = try LorvexZipArchive.archive(entries: [
    .init(path: "a.txt", data: Data("hello".utf8))
  ])
  let central = try #require(centralDirectoryOffsets(zip).first)
  patchUInt32LE(&zip, at: central + 24, 4)

  do {
    _ = try LorvexZipArchive.read(zip)
    Issue.record("expected stored-size mismatch to be rejected")
  } catch let error as LorvexZipArchive.ReadError {
    guard case .malformedHeader(let detail) = error else {
      Issue.record("expected malformedHeader, got \(error)")
      return
    }
    #expect(detail.contains("different compressed and uncompressed sizes"))
  }
}

@Test
func readerRejectsLocalMetadataThatDisagreesWithTheCentralDirectory() throws {
  var zip = try LorvexZipArchive.archive(entries: [
    .init(path: "a.txt", data: Data("hello".utf8))
  ])
  patchUInt16LE(&zip, at: 8, 8)

  do {
    _ = try LorvexZipArchive.read(zip)
    Issue.record("expected local compression-method mismatch to be rejected")
  } catch let error as LorvexZipArchive.ReadError {
    guard case .malformedHeader(let detail) = error else {
      Issue.record("expected malformedHeader, got \(error)")
      return
    }
    #expect(detail.contains("compression methods disagree"))
  }
}

@Test
func readerRejectsLocalPayloadThatOverlapsTheCentralDirectory() throws {
  var zip = try LorvexZipArchive.archive(entries: [
    .init(path: "a.txt", data: Data("hello".utf8))
  ])
  let central = try #require(centralDirectoryOffsets(zip).first)
  patchUInt32LE(&zip, at: central + 20, UInt32(central))
  patchUInt32LE(&zip, at: central + 24, UInt32(central))

  #expect(throws: LorvexZipArchive.ReadError.truncated) {
    _ = try LorvexZipArchive.read(zip)
  }
}

@Test
func readerAcceptsUnsignedDataDescriptorWhoseCRCEqualsTheOptionalSignature() throws {
  // CRC32([ac 0a 7a d5]) == 0x08074b50, the optional descriptor
  // signature. An unsigned descriptor is still legal and must be identified by
  // its complete CRC/size triple rather than by the first word alone.
  let payload = Data([0xAC, 0x0A, 0x7A, 0xD5])
  var zip = try LorvexZipArchive.archive(entries: [
    .init(path: "collision.bin", data: payload)
  ])
  let central = try #require(centralDirectoryOffsets(zip).first)
  let eocd = endOfCentralDirectoryOffset(zip)
  patchUInt16LE(&zip, at: 6, 0x0008)
  patchUInt16LE(&zip, at: central + 8, 0x0008)
  patchUInt32LE(&zip, at: 14, 0)
  patchUInt32LE(&zip, at: 18, 0)
  patchUInt32LE(&zip, at: 22, 0)

  let descriptor: [UInt8] = [
    0x50, 0x4B, 0x07, 0x08,  // CRC32, not a signature in this layout
    0x04, 0x00, 0x00, 0x00,  // compressed size
    0x04, 0x00, 0x00, 0x00,  // uncompressed size
  ]
  zip.insert(contentsOf: descriptor, at: central)
  patchUInt32LE(&zip, at: eocd + descriptor.count + 16, UInt32(central + descriptor.count))

  let entries = try LorvexZipArchive.read(zip)
  #expect(entries.count == 1)
  #expect(entries.first?.path == "collision.bin")
  #expect(entries.first?.data == payload)
}

@Test
func readerRejectsEntryDeclaringOversizedUncompressedSize() throws {
  // Build a valid single-entry archive, then patch the central-directory
  // header's uncompressed-size field to a value far beyond the per-entry cap —
  // exactly what a crafted archive would do to provoke a huge allocation. The
  // reader must reject it up front, before allocating the inflate buffer.
  var zip = try LorvexZipArchive.archive(entries: [
    .init(path: "big.json", data: Data("{}".utf8))
  ])
  let centralSignature: [UInt8] = [0x50, 0x4B, 0x01, 0x02]
  let bytes = Array(zip)
  var centralOffset: Int?
  for i in 0...(bytes.count - 4) where Array(bytes[i..<(i + 4)]) == centralSignature {
    centralOffset = i
    break
  }
  let central = try #require(centralOffset)
  let huge: UInt32 = 0x7FFF_FFFF  // ~2.1 GiB, far above the 256 MiB cap
  zip[central + 24] = UInt8(huge & 0xFF)
  zip[central + 25] = UInt8((huge >> 8) & 0xFF)
  zip[central + 26] = UInt8((huge >> 16) & 0xFF)
  zip[central + 27] = UInt8((huge >> 24) & 0xFF)

  do {
    _ = try LorvexZipArchive.read(zip)
    Issue.record("expected read to reject the oversized entry")
  } catch let error as LorvexZipArchive.ReadError {
    guard case .entryTooLarge(let entry, let declaredSize, let limit) = error else {
      Issue.record("expected entryTooLarge, got \(error)")
      return
    }
    #expect(entry == "big.json")
    #expect(declaredSize == Int(huge))
    #expect(limit == LorvexZipArchive.maxEntryUncompressedBytes)
  }
}

// MARK: - Layered resource limits (compression-bomb / entry-flood defense)

private func patchUInt32LE(_ data: inout Data, at offset: Int, _ value: UInt32) {
  data[offset] = UInt8(value & 0xFF)
  data[offset + 1] = UInt8((value >> 8) & 0xFF)
  data[offset + 2] = UInt8((value >> 16) & 0xFF)
  data[offset + 3] = UInt8((value >> 24) & 0xFF)
}

private func patchUInt16LE(_ data: inout Data, at offset: Int, _ value: UInt16) {
  data[offset] = UInt8(value & 0xFF)
  data[offset + 1] = UInt8((value >> 8) & 0xFF)
}

/// Byte offsets of every central-directory file header (signature `0x02014b50`)
/// in a small test archive, in order.
private func centralDirectoryOffsets(_ data: Data) -> [Int] {
  let signature: [UInt8] = [0x50, 0x4B, 0x01, 0x02]
  let bytes = Array(data)
  var offsets: [Int] = []
  var i = 0
  while i + 4 <= bytes.count {
    if Array(bytes[i..<(i + 4)]) == signature {
      offsets.append(i)
      i += 46
    } else {
      i += 1
    }
  }
  return offsets
}

/// Offset of the end-of-central-directory record (`0x06054b50`).
private func endOfCentralDirectoryOffset(_ data: Data) -> Int {
  let signature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
  let bytes = Array(data)
  var i = bytes.count - 22
  while i >= 0 {
    if Array(bytes[i..<(i + 4)]) == signature { return i }
    i -= 1
  }
  return -1
}

@Test
func readerRejectsAnArchiveDeclaringTooManyEntries() throws {
  // Patch both EOCD central-directory record counts far past the entry cap; the
  // reader must reject up front rather than walk 60k+ headers.
  var zip = try LorvexZipArchive.archive(
    entries: [.init(path: "a.json", data: Data("{}".utf8))])
  let eocd = endOfCentralDirectoryOffset(zip)
  patchUInt16LE(&zip, at: eocd + 8, UInt16(LorvexZipArchive.maxEntryCount + 1))
  patchUInt16LE(&zip, at: eocd + 10, UInt16(LorvexZipArchive.maxEntryCount + 1))

  do {
    _ = try LorvexZipArchive.read(zip)
    Issue.record("expected the reader to reject too many entries")
  } catch let error as LorvexZipArchive.ReadError {
    guard case .tooManyEntries(let count, let limit) = error else {
      Issue.record("expected tooManyEntries, got \(error)")
      return
    }
    #expect(count == LorvexZipArchive.maxEntryCount + 1)
    #expect(limit == LorvexZipArchive.maxEntryCount)
  }
}

@Test
func readerRejectsAMultiDiskEndOfCentralDirectory() throws {
  var zip = try LorvexZipArchive.archive(entries: [
    .init(path: "a.json", data: Data("{}".utf8))
  ])
  let eocd = endOfCentralDirectoryOffset(zip)
  patchUInt16LE(&zip, at: eocd + 4, 1)

  do {
    _ = try LorvexZipArchive.read(zip)
    Issue.record("expected the reader to reject a multi-disk archive")
  } catch let error as LorvexZipArchive.ReadError {
    guard case .malformedHeader(let detail) = error else {
      Issue.record("expected malformedHeader, got \(error)")
      return
    }
    #expect(detail.contains("multi-disk"))
  } catch {
    Issue.record("expected a ZIP read error, got \(error)")
  }
}

@Test
func readerRejectsDisagreeingEndOfCentralDirectoryRecordCounts() throws {
  var zip = try LorvexZipArchive.archive(entries: [
    .init(path: "a.json", data: Data("{}".utf8))
  ])
  let eocd = endOfCentralDirectoryOffset(zip)
  patchUInt16LE(&zip, at: eocd + 8, 0)

  do {
    _ = try LorvexZipArchive.read(zip)
    Issue.record("expected the reader to reject mismatched central-directory counts")
  } catch let error as LorvexZipArchive.ReadError {
    guard case .malformedHeader(let detail) = error else {
      Issue.record("expected malformedHeader, got \(error)")
      return
    }
    #expect(detail.contains("record counts disagree"))
  } catch {
    Issue.record("expected a ZIP read error, got \(error)")
  }
}

@Test
func readerRejectsCentralDirectoryGeometryThatDoesNotEndAtEOCD() throws {
  var zip = try LorvexZipArchive.archive(entries: [
    .init(path: "a.json", data: Data("{}".utf8))
  ])
  let eocd = endOfCentralDirectoryOffset(zip)
  patchUInt32LE(&zip, at: eocd + 12, 0)

  do {
    _ = try LorvexZipArchive.read(zip)
    Issue.record("expected the reader to reject inconsistent central-directory geometry")
  } catch let error as LorvexZipArchive.ReadError {
    guard case .malformedHeader(let detail) = error else {
      Issue.record("expected malformedHeader, got \(error)")
      return
    }
    #expect(detail.contains("offset and size"))
  } catch {
    Issue.record("expected a ZIP read error, got \(error)")
  }
}

@Test
func importRejectsAnUnexpectedEntryHiddenByCountedDownEOCDRecords() throws {
  let encoder = JSONEncoder()
  let manifest = try encoder.encode(
    ExportManifest(
      schemaVersion: ExportManifest.currentSchemaVersion,
      generatedAt: nil,
      appVersion: nil,
      fileCounts: ["tasks": 0]))
  var zip = try LorvexZipArchive.archive(entries: [
    .init(path: "manifest.json", data: manifest),
    .init(path: "tasks.json", data: Data("[]".utf8)),
    .init(path: "attachments/hidden.bin", data: Data([0x01, 0x02, 0x03])),
  ])
  let eocd = endOfCentralDirectoryOffset(zip)
  // Leave the central-directory byte size untouched but claim only the first
  // two records exist. A count-only reader would hide the unexpected third
  // entry from the importer's closed-inventory check.
  patchUInt16LE(&zip, at: eocd + 8, 2)
  patchUInt16LE(&zip, at: eocd + 10, 2)

  do {
    _ = try LorvexDataImporter.decode(zip)
    Issue.record("expected the hidden central-directory entry to invalidate the archive")
  } catch let error as LorvexDataImporter.ImportError {
    guard case .malformedZip(let detail) = error else {
      Issue.record("expected malformedZip, got \(error)")
      return
    }
    #expect(detail.contains("record count does not consume"))
  }
}

@Test
func readerRejectsAnEntryDeclaringAnExcessiveDecompressionRatio() throws {
  // Central-directory uncompressed size patched to inflate ~1,000,000× its 2
  // stored bytes — under the per-entry cap, but a classic compression bomb.
  var zip = try LorvexZipArchive.archive(
    entries: [.init(path: "bomb.json", data: Data("{}".utf8))])
  let central = try #require(centralDirectoryOffsets(zip).first)
  patchUInt32LE(&zip, at: central + 24, 2_000_000)  // uncompressed size

  do {
    _ = try LorvexZipArchive.read(zip)
    Issue.record("expected the reader to reject the decompression ratio")
  } catch let error as LorvexZipArchive.ReadError {
    guard case .compressionRatioExceeded(let entry, _, _, let limit) = error else {
      Issue.record("expected compressionRatioExceeded, got \(error)")
      return
    }
    #expect(entry == "bomb.json")
    #expect(limit == LorvexZipArchive.maxCompressionRatio)
  }
}

@Test
func readerRejectsAnArchiveExceedingTheAggregateUncompressedBudget() throws {
  // Three entries whose declared (uncompressed == compressed, ratio 1) sizes sum
  // past the aggregate cap: two at the per-entry cap plus one more tips it over.
  var zip = try LorvexZipArchive.archive(entries: [
    .init(path: "a.json", data: Data("{}".utf8)),
    .init(path: "b.json", data: Data("{}".utf8)),
    .init(path: "c.json", data: Data("{}".utf8)),
  ])
  let centrals = centralDirectoryOffsets(zip)
  #expect(centrals.count == 3)
  let cap = UInt32(LorvexZipArchive.maxEntryUncompressedBytes)
  for central in centrals.prefix(2) {
    patchUInt32LE(&zip, at: central + 20, cap)  // compressed size (keep ratio 1:1)
    patchUInt32LE(&zip, at: central + 24, cap)  // uncompressed size (== per-entry cap)
  }
  patchUInt32LE(&zip, at: centrals[2] + 20, 1_048_576)
  patchUInt32LE(&zip, at: centrals[2] + 24, 1_048_576)

  do {
    _ = try LorvexZipArchive.read(zip)
    Issue.record("expected the reader to reject the aggregate uncompressed size")
  } catch let error as LorvexZipArchive.ReadError {
    guard case .totalUncompressedTooLarge(let total, let limit) = error else {
      Issue.record("expected totalUncompressedTooLarge, got \(error)")
      return
    }
    #expect(total > limit)
    #expect(limit == LorvexZipArchive.maxTotalUncompressedBytes)
  }
}

@Test
func importLimitsRejectMaterializedDataAboveTheSourceBound() {
  #expect(throws: LorvexImportLimits.SourceTooLargeError.self) {
    try LorvexImportLimits.assertWithinSourceBound(
      Data(count: LorvexImportLimits.maxSourceBytes + 1))
  }
  // A normal-sized payload is accepted.
  #expect(throws: Never.self) {
    try LorvexImportLimits.assertWithinSourceBound(Data(count: 4096))
  }
}

@Test
func renderZipIsDeterministicForIdenticalInput() throws {
  let payload = LorvexDataExportPayload(
    tasks: [
      ExportTask(
        id: "task-1", title: "Buy milk", notes: "", priority: "P2", status: "open",
        dueDate: nil, estimatedMinutes: nil, tags: [])
    ],
    lists: [ExportList(id: "list-1", name: "Inbox", description: "")]
  )
  let first = try LorvexDataExporter.renderZip(
    payload: payload, generatedAt: "2026-05-28T00:00:00Z", appVersion: "1.2.3")
  let second = try LorvexDataExporter.renderZip(
    payload: payload, generatedAt: "2026-05-28T00:00:00Z", appVersion: "1.2.3")
  #expect(first == second)
}

// MARK: - Exporter ZIP packaging

@Test
func exporterZipContainsPerCategoryFilesAndManifest() throws {
  let payload = LorvexDataExportPayload(
    tasks: [
      ExportTask(
        id: "task-1", title: "Buy milk", notes: "", priority: "P2", status: "open",
        dueDate: nil, estimatedMinutes: nil, tags: [])
    ],
    lists: [ExportList(id: "list-1", name: "Inbox", description: "")]
  )
  let zip = try LorvexDataExporter.renderZip(
    payload: payload, generatedAt: "2026-05-28T00:00:00Z", appVersion: "1.2.3")

  let dir = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("lorvex-zip-exporter-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }
  let zipURL = dir.appendingPathComponent("export.zip")
  try zip.write(to: zipURL)

  let listing = try runUnzip(arguments: ["-l", zipURL.path])
  let listingText = String(decoding: listing.stdout, as: UTF8.self)
  #expect(listingText.contains("manifest.json"))
  #expect(listingText.contains("tasks.json"))
  #expect(listingText.contains("lists.json"))
  // Absent categories must not produce files.
  #expect(!listingText.contains("habits.json"))

  let tasksFile = try runUnzip(arguments: ["-p", zipURL.path, "tasks.json"])
  #expect(String(decoding: tasksFile.stdout, as: UTF8.self).contains("task-1"))

  let manifestFile = try runUnzip(arguments: ["-p", zipURL.path, "manifest.json"])
  let manifestText = String(decoding: manifestFile.stdout, as: UTF8.self)
  let manifest = try JSONDecoder().decode(ExportManifest.self, from: manifestFile.stdout)
  #expect(ExportManifest.currentSchemaVersion == "1")
  #expect(manifest.schemaVersion == ExportManifest.currentSchemaVersion)
  #expect(manifestText.contains("2026-05-28T00:00:00Z"))
  #expect(manifestText.contains("1.2.3"))
}

// MARK: - Deflate (real Tauri export archive)

/// The reader must inflate deflate-compressed entries (method 8), which is what
/// the Rust `zip` crate the Tauri exporter uses emits. Exercised against the
/// committed golden archive so a regression in the inflate path is caught.
@Test
func readsDeflateCompressedTauriExportFixture() throws {
  var url = URL(fileURLWithPath: #filePath)
  for _ in 0..<5 { url.deleteLastPathComponent() }  // …/LorvexAppleTests → repo root
  let fixture = url.appendingPathComponent("spec/fixtures/tauri-export-golden.zip")
  let data = try Data(contentsOf: fixture)

  let entries = try LorvexZipArchive.read(data)
  let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.data) })

  // manifest.json + the seven JSONL streams are all present and inflated.
  #expect(byName["manifest.json"] != nil)
  let manifest = try #require(byName["manifest.json"])
  let manifestText = String(decoding: manifest, as: UTF8.self)
  #expect(manifestText.contains("\"format_version\""))

  // entities.jsonl inflates to readable JSON lines with the seeded task.
  let entities = try #require(byName["entities.jsonl"])
  let entitiesText = String(decoding: entities, as: UTF8.self)
  #expect(entitiesText.contains("\"entity_type\""))
  #expect(entitiesText.contains("task-1"))

  // Empty streams inflate to zero bytes (the deflate empty-block case).
  #expect(byName["audit.jsonl"] == Data())
}
